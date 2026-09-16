---
description: Set up a repo's public face — README, license, and every piece of GitHub metadata worth setting
---

Set up this repo's public face: a README, a license, and every piece of GitHub metadata worth setting.

**Come up for air whenever the answer is a judgement call rather than a lookup.** Stop and ask before: choosing a license; enabling branch protection or required reviews; disabling a feature tab that already holds content (open issues, a wiki with pages, existing discussions); and any case where the repo's own docs disagree about what the project is. Leave visibility exactly as you found it, and leave pushing to me — commit and hand back.

Safe to re-run. On a repo that is already partly set up, report what is already correct and propose only the diff.

Work in this order.

1. **Audit before writing anything.** Read the repo's own docs (existing README, AGENTS.md/CLAUDE.md, CONTRIBUTING, any constitution/ADR/vocabulary files), the manifest, the CI workflows, and `gh repo view`. Take the homepage from `gh api repos/{owner}/{repo}/pages` where a Pages deploy exists. Note the visibility, since it decides which security features are free. Done when every item in step 4's list is marked set, unset, or wrong.

   Where I name a repo whose shape I already like, read its settings with `gh api repos/{owner}/{repo}` and propose this repo as a diff against that one.

2. **README:** invoke the `readme-coauthorship` skill and follow it. Let it ask its own questions; answering them on my behalf produces a README about the repo you inferred.

3. **License:** where no LICENSE file exists, ask which license, write it, then align the manifest's license field. That field usually carries an `npm init` or `cargo init` default contradicting the real choice.

4. **Propose every GitHub setting as one preview and wait for my approval before writing anything to GitHub.** Cover:

   - description (give me 2–3 concrete options to choose between), homepage, topics
   - the six merge settings, below
   - security features free at this visibility: secret scanning, push protection, Dependabot alerts, Dependabot security updates, code scanning/CodeQL
   - Dependabot version updates, which are a `.github/dependabot.yml` file rather than a toggle. Propose one with an interval and let me decline: bump PRs earn their noise on a repo with CI and an active maintainer, and are pure noise on one that has never had a PR. The file lands in step 7's commit, not step 5's settings apply.
   - feature tabs holding nothing: Issues, Projects, Wiki, Discussions
   - priority labels `P0`, `P1`, `P2`, each with a description stating the test for that level. Create them with `gh label create --force`, which also updates one that already exists and keeps this step re-runnable. Reuse these unless I say otherwise: P0 `b60205` "Drop everything: broken for everyone, or blocking every other ticket"; P1 `d93f0b` "Next up: blocks a milestone, or no workaround exists"; P2 `fbca04` "Queued: real, but survivable and schedulable". A level nobody can test against gets applied by mood.

   **The merge settings, and why they are worth the space.** `squash_merge_commit_message: PR_BODY` hard-wraps every squashed commit body at ~72 columns: the squash dialog pre-fills its description textarea wrapped, and confirming commits those newlines, so nothing about how the message was authored survives. Default to `COMMIT_MESSAGES`, which passes commit bodies through verbatim and is the better record anyway, since commit messages describe the change while a PR body describes the review. Reach for `PR_BODY` only where the repo habitually ships PRs full of "fix typo" commits, and accept the wrapping there. For a **merge** commit the branch's commits survive underneath, making the merge commit a junction marker rather than the record: set `merge_commit_title: PR_TITLE` (the default spends the subject line on a branch name) and `merge_commit_message: BLANK` (`PR_BODY` duplicates reasoning that already exists one level down). Where I read history with `git log --first-parent`, say so, because that argues for `PR_BODY`. Also set `delete_branch_on_merge` and decide `allow_auto_merge`.

5. **Apply, then read every setting back** and show me the value GitHub returns for each. Done when each proposed setting has a confirmed value beside it.

6. **Mirror** the approved description and topics into the manifest's description, keywords, and author fields where those are empty.

7. Run the repo's own checks, derived from the manifest scripts and the CI workflow, then commit.

Gotchas that cost a run to find:

- `gh repo edit --add-topic` accepts a subset of a long topic list and drops the rest without erroring. Set topics with `gh api -X PUT repos/{owner}/{repo}/topics` and read the count back.
- GitHub detects a license only from the default branch, so `licenseInfo` stays null until the LICENSE commit is pushed. Leave it alone until then.
- Dependabot security updates require vulnerability alerts enabled first.
- `delete_branch_on_merge` defaults off and reads as on, because branches disappearing after a merge looks identical to somebody deleting them by hand. Check the value.
- Dependabot malware alerts and grouped security updates have no REST API. `security_and_analysis` accepts only `advanced_security`, `code_security`, and the `secret_scanning_*` properties, so name both as web UI follow-ups. Malware alerts are worth turning on anywhere they're offered, since they fire only on packages flagged malicious; whether a private repo on a free plan gets them is unverified. Grouped updates only matter where there is enough dependency traffic to group.
- The social preview image has no `gh` command. Name it as a follow-up for the web UI.
