# Delegation

This file decides which model a delegated task goes to, and what that task inherits when it gets there.

Read it before any dispatch, fan-out or not. Where a skill's own routing table disagrees with this file, this file wins. A skill's table is scoped to that skill's workflow, and this one covers every delegation.

## Two Questions

### Does This Task Define the Spec, or Implement Against One?

Spec-defining work doesn't delegate at all. Deciding what "done" means, picking an interface, settling an ambiguity somebody wrote down, reading a merged diff against the plan it came from—that stays in session, on whatever model the session is running. Delegation that also delegates the judgment of whether the work came back right saves nothing. It moves the mistake somewhere nobody is looking.

That question ends most routing calls by itself. When it doesn't:

### Can Correctness Be Checked Without Reading Intent?

The cheaper the check, the cheaper the rung. Correctness a script settles routes low. Correctness that needs the artifact read against a stated spec routes to the middle. Correctness only visible to somebody who already knows what the work was for routes to the top.

## The Rungs

| Rung | What routes here | Example |
| --- | --- | --- |
| stays in session | spec-defining work, and every gate on delegated output | deriving a wave table; reading a merged diff against its plan |
| `haiku` | mechanical transcription, where a script settles correctness | a repo-wide grep-and-report; a rename; formatting |
| `sonnet` | implementation against a settled spec, checked against stated behavior | a bats case written to behavior the spec already fixed |
| `opus` | correctness you can only judge against intent, or real blast radius: auth, payments, migrations, deletes, infra, public API | a README rewrite, where every claim has to be checked against the code it describes; any task whose spec is ambiguous |
| `fable` | explicit assignment, and the rung above `opus` after an `opus` task fails | — |

Name the rung on every dispatch. An omitted model inherits the session's, which is usually the most expensive one available, and the routing evaporates while the run still looks correct.

A task sitting between two rungs goes up. Guessing downward costs a revert, a retry, and the gate that caught it. Guessing upward costs the difference in price.

`haiku`, `sonnet`, `opus`, and `fable` are today's lineup. The family turns over and these names outlive the mapping, so when it changes, re-check what each rung points at instead of assuming it still means what it meant here.

## When a Skill's Table Says Otherwise

`divvy-up` routes docs and changelogs to `haiku`. In my skills repo a README task failed its gate on `sonnet` and passed on `opus`: every claim in it had to be checked against the file it described, which is the second question's top row and not a documentation job at all. Route on what checking the work takes, not on what kind of file it is.

## The Floor

If writing the brief—the task, the files it owns, the done-when, the context it needs so it doesn't guess—costs more than doing the task, do the task.

One thing overrides the floor. A task whose output would flood the session earns a dispatch however small it is: a grep across the whole repo, ten files read to answer one question. The parallelism is beside the point there. What you're buying is the context you didn't spend.

## What Every Delegated Task Inherits

Put these in the dispatch. A subagent has no other way to learn them, and a repo's own agent docs are usually written for an agent working alone.

1. The files it owns. Write only those, and report every path touched, including the ones you didn't mean to. A stray write clobbers a peer's work that the writer never saw and can't reconcile with.
2. Delete nothing it didn't create. A subagent reads a deletion as cleanup. Whoever dispatched it reads a missing file with no author.
3. The verification command, run, with its real output. Report what the command printed, not a characterization of it. "Tests pass" is evidence of what the subagent believed; the output is evidence of what happened.
4. One rung up on failure. Revert the paths the task owned, then re-dispatch it alone one rung up with the failure attached. Revert first, or the next agent spends its budget debugging the last one's leftovers. Nothing sits above `fable`, so a failure there stops the run.
