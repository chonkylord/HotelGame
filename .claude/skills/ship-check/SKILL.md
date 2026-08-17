---
name: ship-check
description: Pre-ship quality gate for a Bricklayer Roblox project — diagnostics, tests, conflict files, trash, and a smoke playtest. Use before declaring work done, before publishing, or when asked "is this ready?".
---

# /ship-check — is this place ready?

Run every gate, then present one pass/fail table. Do not stop at the first
failure — collect them all.

## Gates

1. **Diagnostics clean** — `bl_analyze` (whole mirror): 0 errors. Warnings are
   reportable but not blocking; list the top few if noisy.
2. **Tests green** — `bl_run_tests`: 0 failures, and at least one spec exists
   (a place with zero specs gets a warning, not a pass).
3. **No unresolved conflicts** — Grep the mirror for `*.conflict.luau`. Any hit
   is a blocker: reconcile and delete.
4. **No leftover debris** —
   - `bl_get_tree` on `game.ServerStorage._bricklayer_trash`: anything there
     was deleted this session; confirm with the user it can stay trashed.
   - Grep `src/` for obvious debug leftovers: `print("` lines added during this
     session's work, `warn("TODO`, `--!nocheck`.
5. **Sync healthy** — `bl_status`: connected, not paused, script count matches
   expectations.
6. **Smoke playtest** — the `/playtest` skill with no expectation (game starts,
   ~15s with zero `error`-level console lines).

## Report format

| Gate | Result | Notes |
|---|---|---|
| Diagnostics | ✅/❌ | … |
| Tests | ✅/❌ | pass/fail counts |
| Conflicts | ✅/❌ | files |
| Debris | ✅/⚠️ | trash contents, debug prints |
| Sync | ✅/❌ | … |
| Smoke playtest | ✅/❌ | errors seen |

Verdict line at the end: **SHIP** only when nothing is ❌; otherwise list what
blocks and the smallest fix for each.
