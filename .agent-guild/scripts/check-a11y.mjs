#!/usr/bin/env node
// Run axe-core against a URL in BOTH light and dark mode and fail on any
// violation. Dark-mode-only contrast failures are the classic "looks fine to
// the sighted author, invisible to a real user" bug—checking one theme isn't
// enough.
//
//   .agent-guild/scripts/check-a11y.mjs <url> [--wait <selector>]
//
// Deps (playwright + @axe-core/playwright) self-bootstrap on first run so the
// kit stays copy-in portable: no global install, everything lands under
// .agent-guild/scripts/node_modules (gitignored). First run needs network and a couple of
// minutes; after that it's fast.
//
// Exit codes: 0 clean in both themes; 1 violations found (clause FAIL);
// 3 infra error—deps unavailable offline, or the URL wouldn't load (ERROR,
// not a worker failure).
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));

function usage(msg) {
  if (msg) console.error(msg);
  console.error("usage: check-a11y.mjs <url> [--wait <selector>]");
  process.exit(3);
}

const args = process.argv.slice(2);
if (args.length < 1) usage();
const url = args[0];
let waitFor = null;
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--wait") waitFor = args[++i];
}
if (!/^https?:\/\//.test(url)) usage(`not an http(s) url: ${url}`);

function ensureDeps() {
  if (existsSync(join(SCRIPT_DIR, "node_modules", "@axe-core", "playwright"))) {
    return;
  }
  console.error("check-a11y: installing deps (first run, needs network)…");
  try {
    execSync("npm install --no-audit --no-fund", {
      cwd: SCRIPT_DIR,
      stdio: "inherit",
    });
    // Chromium binary is separate from the npm package.
    execSync("npx --yes playwright install chromium", {
      cwd: SCRIPT_DIR,
      stdio: "inherit",
    });
  } catch (e) {
    console.error(
      "check-a11y: dependency bootstrap failed—offline? " +
        "This is an infra ERROR, not an accessibility failure.\n" +
        (e.message || e)
    );
    process.exit(3);
  }
}

async function run() {
  ensureDeps();

  let chromium, AxeBuilder;
  try {
    ({ chromium } = await import(join(SCRIPT_DIR, "node_modules", "playwright", "index.js")));
    AxeBuilder = (await import(join(SCRIPT_DIR, "node_modules", "@axe-core", "playwright", "dist", "index.js"))).default;
  } catch (e) {
    console.error("check-a11y: cannot load deps after install—infra ERROR\n" + (e.message || e));
    process.exit(3);
  }

  let browser;
  try {
    browser = await chromium.launch();
  } catch (e) {
    console.error("check-a11y: chromium failed to launch—infra ERROR\n" + (e.message || e));
    process.exit(3);
  }

  const allViolations = [];
  try {
    for (const scheme of ["light", "dark"]) {
      const context = await browser.newContext({ colorScheme: scheme });
      const page = await context.newPage();
      try {
        const resp = await page.goto(url, { waitUntil: "load", timeout: 30000 });
        if (!resp || !resp.ok()) {
          console.error(
            `check-a11y: ${url} returned ${resp ? resp.status() : "no response"}—infra ERROR`
          );
          await browser.close();
          process.exit(3);
        }
        if (waitFor) await page.waitForSelector(waitFor, { timeout: 15000 });
      } catch (e) {
        console.error(`check-a11y: ${url} failed to load (${scheme})—infra ERROR\n` + (e.message || e));
        await browser.close();
        process.exit(3);
      }
      const results = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
        .analyze();
      for (const v of results.violations) {
        allViolations.push({ scheme, id: v.id, impact: v.impact, help: v.help,
          nodes: v.nodes.map((n) => n.target.join(" ")) });
      }
      await context.close();
    }
  } finally {
    await browser.close();
  }

  if (allViolations.length === 0) {
    console.log(`OK: no axe violations in light or dark mode—${url}`);
    process.exit(0);
  }

  console.error(`ACCESSIBILITY VIOLATIONS (${allViolations.length})—${url}`);
  for (const v of allViolations) {
    console.error(`  [${v.scheme}] ${v.id} (${v.impact}): ${v.help}`);
    for (const sel of v.nodes) console.error(`      → ${sel}`);
  }
  process.exit(1);
}

run().catch((e) => {
  console.error("check-a11y: unexpected error—infra ERROR\n" + (e.stack || e));
  process.exit(3);
});
