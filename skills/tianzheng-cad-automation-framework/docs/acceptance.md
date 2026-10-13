# Safety and Acceptance Model

## Security baseline

A public or shared implementation package must exclude:

- customer and project names;
- site names and identifying geography;
- real DWG files and audit exports;
- signatures, reviewer names, title blocks, and logos;
- local machine paths;
- process IDs, window handles, object handles, and object counts from private runs;
- execution logs, screenshots, chat text, tokens, credentials, and personal identifiers.

Documentation should describe patterns using generic examples such as `source.dwg`, `sheet-01`, `road-centerline`, or synthetic coordinates.

## File protection

1. Record the source drawing hash before work.
2. Operate only on an isolated copy.
3. Keep formal sources, active work files, test masters, checkpoints, and outputs separated.
4. Use save-copy or a controlled checkpoint route for test iterations.
5. Confirm after work that the original source hash is unchanged.

A copied file is not the same as a native save. If the application has unsaved state, the controlled save operation must prove that in-memory state has reached disk before checkpointing.

## Session ownership

The controller must identify the exact application process, window, and document it owns. It must not connect to a user's unrelated CAD session.

Safe cleanup may terminate only a process or orphan that current task ownership evidence identifies. Unknown, user-owned, unsaved, or ambiguous CAD processes are stopped and reported, not killed or taken over.

## Dialog handling

Known dialogs are matched by exact, version-specific signatures: process, window class/title, body text, and button identity. The default action for an unknown dialog is to stop and report.

Typical rules:

- unresolved external reference: ignore the missing reference and report it; do not re-bind;
- drawing recovery notification: close and report; do not write back automatically;
- overwrite-source prompt: stop;
- unknown repair/update/compatibility prompt: stop.

## Command adapter restrictions

The controller should submit structured requests, not arbitrary command text. Approved adapters only run whitelisted command recipes.

Disallowed by default:

- dynamic evaluation of arbitrary code;
- raw mouse-coordinate replay;
- guessing command prompts from another CAD product or Tianzheng version;
- continuing after an unknown prompt;
- writing on a source drawing;
- saving before per-object acceptance.

## Acceptance levels

| Level | Question answered | Minimum evidence |
|---|---|---|
| Command complete | Did the command finish? | Idle command state and execution receipt |
| Object accepted | Were intended native objects created or changed? | Object counts, types, handles, source mapping, style/layer checks |
| File persisted | Did changes survive save? | Controlled save state and on-disk file identity |
| Reopen accepted | Are results stable after close/reopen? | Reopen audit of intended objects |
| Visual accepted | Does the drawing read correctly? | Model/layout screenshot or machine-readable visual-region check plus review |
| Scope accepted | Did only intended scope change? | Before/after protected-object comparison and source hash check |

The command-complete level never substitutes for later levels.

## Rollback

Each mutation batch should define rollback before execution. Useful strategies include:

- delete only objects created by the current attempt;
- restore a named prior checkpoint;
- reverse a bounded control-point change from recorded values;
- stop before save when a late acceptance check fails.

Rollback must be scoped to the current batch. It must not delete pre-existing objects, user content, or unrelated annotations.

## Run receipt

A complete receipt records:

1. input identity and isolation result;
2. workflow/version and adapter identity;
3. requested scope and approval state;
4. planned object groups;
5. execution result;
6. created/changed/deleted/protected counts;
7. failed subset and reason;
8. acceptance level reached;
9. output/checkpoint identity;
10. unresolved dependencies and next safe action.

The receipt should be small enough to review but concrete enough to resume. It should link to evidence rather than embed raw production data.
