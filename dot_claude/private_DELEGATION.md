# Delegation

This file decides which model a delegated task goes to, and what that task inherits when it gets there.

Read it before any dispatch, fan-out or not. This file is the default for any dispatch. Anything that says how it dispatches owns that while it's driving—a skill, project instructions, a workflow's own lifecycle—since its table is written for the work in front of it. Where it is silent, contradicts itself, or leaves the call open, this file decides.

## Two Questions

### Does This Task Define the Spec, or Implement Against One?

Spec-defining work doesn't delegate at all. Deciding what "done" means, picking an interface, settling an ambiguity somebody wrote down—that stays in session, on whatever model the session is running. Delegation that also delegates the judgment of whether the work came back right saves nothing. It moves the mistake somewhere nobody is looking.

An ambiguous spec is this question's business, not a reason to buy a bigger model. Settle the ambiguity, then route the settled task. A rung up doesn't resolve an ambiguity, it produces a more confident guess at one.

That question ends most routing calls by itself. When it doesn't:

### Can Correctness Be Checked Without Reading Intent?

The cheaper the check, the cheaper the rung. Correctness a script settles routes low. Correctness that needs the artifact read against a stated spec routes to the middle. Correctness only visible to somebody who already knows what the work was for routes to the top.

A README rewrite reads like a docs job until you ask what checking it takes. Checking means reading every claim against the code it describes, which puts the rewrite on the top rung. Route on the check, not on the kind of file.

## The Rungs

| Rung | What routes here | Example |
| --- | --- | --- |
| stays in session | spec-defining work, and the ruling on whatever a check reports | deciding an interface; accepting or rejecting a verdict |
| `haiku` | mechanical transcription, where a script settles correctness | a repo-wide grep-and-report; a rename; formatting |
| `sonnet` | implementation against a settled spec, checked against stated behavior | a bats case written to behavior the spec already fixed |
| `opus` | correctness you can only judge against intent, or anything under the irreversibility rule below | a README rewrite |
| `fable` | explicit assignment, and the rung above `opus` after an `opus` task fails | — |

Name the rung on every dispatch that picks a model. An omitted model usually inherits the session's, which is the most expensive one available, and a typed agent takes whatever its own definition names instead. Either way the routing evaporates while the run still looks correct. A lane that carries no model of its own has no rung to name, and naming one breaks the only contract it does have—agent-guild's courier relays to another vendor's CLI, so there is no rung on this ladder that means anything to it.

A task sitting between two rungs goes up. Guessing downward costs a revert, a retry, and the gate that caught it. Guessing upward costs the difference in price.

`haiku`, `sonnet`, `opus`, and `fable` are today's lineup. The family turns over and these names outlive the mapping, so when it changes, re-check what each rung points at instead of assuming it still means what it meant here.

## Irreversibility Beats Both Questions

Both questions assume a wrong answer can be thrown away. Auth, payments, migrations, deletes, and infra are where that assumption fails. The check runs after the damage, and the retry below has nothing left to revert. A script can confirm the tables are gone and report a pass.

So this overrides the routing above. Work that can't be undone goes to `opus` however cheap its check looks, and the cheapness of the check is the trap—a delete is about as script-checkable as work gets. `fable` is an escalation destination, never a routing answer.

## Delegating a Check Is Fine

An independent checker that re-derives a worker's claims beats reading the worker's own report. Dispatch those freely, and route them by the same two questions as anything else.

The ruling is the part that stays with you: whether the verdict is right, and whether the task is done. Hand that to something you dispatched and nothing is left watching.

## The Floor

If writing the brief—the task, the files it owns, the done-when, the context it needs so it doesn't guess—costs more than doing the task, do the task.

One thing overrides the floor. A task whose output would flood the session earns a dispatch however small it is: a grep across the whole repo, ten files read to answer one question. Speed is beside the point there. What you're buying is the context you didn't spend.

## What Every Delegated Task Inherits

Put these in the dispatch. A subagent has no other way to learn them, and a repo's own agent docs are usually written for an agent working alone.

1. The files it owns. Write only those, and report every path touched, including the ones you didn't mean to. A stray write clobbers a peer's work that the writer never saw and can't reconcile with. Don't edit an owned path yourself while its task is in flight either, because the revert on failure can't tell your edit from the worker's.
2. Delete only a path the task names explicitly, or one that's in the files it owns. Everything else, leave alone. A subagent reads an unassigned deletion as cleanup. Whoever dispatched it reads a missing file with no author.
3. The verification command, actually run, with its real output. Report what the command printed, not a characterization of it. "Tests pass" is evidence of what the subagent believed; the output is evidence of what happened.
4. One rung up on failure, where nothing else owns the retry. Inside a protocol running its own retry ladder, that ladder decides the tier, the counter, and how the tree gets restored, and nothing else in this item applies. Everywhere else, revert the paths the task owned to the state captured before the dispatch went out, not to HEAD or to clean—ownership says where the worker could write, not that the path started clean. With no captured baseline, the owned paths have to be clean before dispatch, or the work doesn't get delegated. Then re-dispatch it one rung up with the failure attached. Revert first, or the next agent spends its budget debugging the last one's leftovers. Nothing sits above `fable`, so a failure there stops the run.
