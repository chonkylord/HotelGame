---
name: playtest
description: Run a playtest in Roblox Studio and verify an expectation — start play mode, drive the character/input, read console output and logs, capture the screen, then stop and report. Use when asked to playtest, try the game, verify a mechanic in-game, or reproduce a runtime bug.
---

# /playtest — verify behavior in a running game

Input: an expectation to verify, e.g. `/playtest "touch a coin, expect +10 score"`.
If no expectation is given, do a smoke run: game starts, no errors in the first
~15 seconds.

## Before starting

1. `bl_status` — confirm Studio is connected and sync is not paused. If edits
   were just made, confirm `bl_analyze` is clean (never playtest code with type
   or syntax errors — fix first).
2. Note the current `bl_get_logs` cursor so you only read logs from this run.
3. Remember: **while play mode runs, disk→Studio sync pauses** — file edits
   queue and apply after stop. Don't edit-and-expect-live-changes mid-playtest.
   (Edits made *before* play are flushed into Studio automatically — a
   pre-playtest hook fires when you call `start_stop_play`.)

## The loop

1. `start_stop_play` (built-in) → start play solo.
2. Drive the scenario:
   - `character_navigation` to walk/jump the character to targets;
     `bl_teleport_character` when only the destination matters.
   - `user_keyboard_input` / `user_mouse_input` for abilities, UI clicks.
   - `bl_wait_for` for timing: one call waits server-side until a Luau
     expression is truthy (`"game.Players.Player1.leaderstats.Coins.Value >= 10"`,
     max 30s per call — call again to keep waiting).
   - For other setup or assertions inside the running game, `execute_luau`
     with the play-mode datamodel context — read-only checks preferred.
3. Observe:
   - `get_console_output` (built-in) and `bl_get_logs` from your saved cursor
     (contexts `play-server` / `play-client`) — errors here are findings.
   - `bl_screenshot` when visual confirmation matters (did the coin vanish?
     did the UI update?). It captures the Studio window at OS level, so it
     works **during play mode** — the built-in `screen_capture` is edit-time
     only. In edit mode, `bl_frame_camera` first aims the camera at the thing
     you want to see.
4. `start_stop_play` → stop. Confirm `bl_status` shows sync resumed.

## Report

State plainly: what was expected, what was observed (console lines, state
values, screenshot description), verdict (confirmed / failed / inconclusive),
and any errors seen that are unrelated to the expectation. If the expectation
failed, propose the next diagnostic step — don't silently retry more than once.
