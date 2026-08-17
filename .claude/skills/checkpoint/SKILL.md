---
name: checkpoint
description: Snapshot or restore the whole project state (mirror files + Studio, via git refs and undo waypoints). Use before risky multi-file changes, or to roll back after something went wrong — "checkpoint this", "roll back", "undo everything since my last prompt".
---

# /checkpoint — save and restore whole-project state

Input: optionally `save <label>`, `list`, or `restore [id-or-label]`.
Bare `/checkpoint` = save with a label describing the work in progress.

## How it works

- `bl_checkpoint {label}` snapshots the mirror as a git commit under
  `refs/bricklayer/checkpoints/*` — your branch, index, and history are never
  touched — and drops a matching waypoint in Studio's undo stack.
- Every user prompt also auto-checkpoints (`label: prompt`) via a hook, so
  "undo everything since my last message" is always one rollback away.
- `bl_rollback {to?}` restores the files on disk (default: latest checkpoint)
  and lets normal sync carry them into Studio. Studio-side, the rollback is
  itself undoable (Ctrl+Z) — nothing is ever unrecoverable.

## Rules

1. Before a risky or sprawling change (multi-file refactor, deleting scripts),
   run `bl_checkpoint` with a descriptive label. Cheap insurance.
2. To restore: `bl_list_checkpoints`, pick the id (or unique label), then
   `bl_rollback`. Confirm with the user before rolling back work they may
   want — show what will be restored/deleted from the tool result.
3. After a rollback, run `bl_analyze` and tell the user exactly what state
   the project is now in (which checkpoint, what changed).
4. Checkpoints are mirror-mode only. In a Rojo project, use git in the
   repo directly (commit, stash, revert) — the files are already the truth.
