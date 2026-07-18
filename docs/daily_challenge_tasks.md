# Daily Seed / Challenge Run — Implementation Tasks

Slices `docs/daily_challenge_spec.md` (issue #14) into small, ordered,
vertical deliverables. Implement **in order**. Each task compiles on its own,
keeps the game playable, and either adds a headless-tested unit or an
observable behavior — nothing is left half-wired between tasks. Do not start a
task until the previous one is done.

**Conventions (from `CLAUDE.md`):** snake_case names; structured logging at
state transitions with subsystem prefixes; no comments that restate code; edit
existing files, add new ones only when the task says so. Targets Godot 4.6.
Gameplay randomness must go through `RunState.rng` — never global
`randi()`/`shuffle()`/`pick_random()`.

**The through-line:** every gameplay draw moves onto one seeded RNG owned by
`RunState`. Tasks 1–3 build tested, side-effect-free logic (seed, persistence,
share text). Task 4 introduces the seeded RNG and wires seeding into every
launch path *without changing draws yet*. Task 5 migrates the draws — the
correctness core, guarded by a live determinism diff. Tasks 6–7 surface the
mode. Task 8 documents the new rule.

---

## Preflight — confirm the v2 baseline (blocking gate, no code)

The spec targets the **tile-modifiers-v2** tree (premium cells #24 + word
multipliers/wildcards #25). This feature branch was cut from `main`
(`e5cedcc`), which does **not** contain them. Every code reference below
(`board.gd::reroll_premiums`, `main.gd::_roll_modifier`,
`game_core.gd::_reroll_premiums`, the `MOD_WILD` upgrade logic) exists only on
the v2 tree. Implementing on `main` would migrate a *smaller, different* set of
RNG sites and silently miss the premium/wildcard streams when the trees merge.

**Gate:**

```
git grep -n "func reroll_premiums" -- scripts/board.gd
```

- **Match →** you are on the v2 tree; proceed to Task 1.
- **No match →** rebase this branch onto the branch that carries #24/#25
  (currently `claude/repo-issues-roi-analysis-e5fb51`, or `main` once they
  land there) **before writing any code**:
  `git rebase claude/repo-issues-roi-analysis-e5fb51`.

Re-run the audit grep (Task 5 Verify) after any later rebase/merge.

---

## Task 1 — Daily seed function + `Mode.DAILY` + seed-pin test (TD1)

**Goal:** Add the date→seed function and the DAILY mode identity, plus the
first headless test. The game is unchanged (DAILY is unreachable and nothing
is seeded yet); this is pure, tested logic.

### 1a. `scripts/run_state.gd` — mode identity

1. Add `DAILY` to the enum (append last so existing ordinals are stable):

```gdscript
enum Mode { EASY, MEDIUM, HARD, ENDLESS, DAILY }
```

2. Fix `is_difficulty_mode()` — the current `return mode != Mode.ENDLESS`
   would wrongly classify DAILY as a difficulty mode. Key off the table that
   actually defines difficulty modes:

```gdscript
func is_difficulty_mode() -> bool:
	return DIFFICULTY_TARGETS.has(mode)
```

This one change routes DAILY down every existing Endless `else`-branch
(target curve in `reset()`/`_advance_round`, the loss path in
`register_turn_score`, the HUD round string) — no new progression branches.

3. Add `"Daily"` to `mode_name()`:

```gdscript
func mode_name() -> String:
	match mode:
		Mode.EASY:   return "Easy"
		Mode.MEDIUM: return "Medium"
		Mode.HARD:   return "Hard"
		Mode.DAILY:  return "Daily"
		_:           return "Endless"
```

4. Add the seed function (static — callable from headless tests without the
   autoload; `String.hash()` is a stable fixed algorithm):

```gdscript
static func daily_seed_for(date_utc: String) -> int:
	return hash("scrabblerabble-daily-%s" % date_utc)
```

### 1b. New file `scripts/sim/tests/test_daily.gd`

Loads `run_state.gd` as a **plain script**, never the autoload (which doesn't
exist under `--script`, per CLAUDE.md). Follow the existing `test_*`→`bool`,
`push_error`-on-fail convention.

```gdscript
class_name TestDaily
extends RefCounted

const RS = preload("res://scripts/run_state.gd")

# TD1 - Seed is stable, date-sensitive, and repeatable.
func test_td1_daily_seed_pin() -> bool:
	# Pin the current hash so a future String.hash() change is noticed here
	# rather than by players. Record the printed value on first run and paste
	# it in as EXPECTED below.
	var EXPECTED := RS.daily_seed_for("2026-01-01")   # replace with the literal int once observed
	var got := RS.daily_seed_for("2026-01-01")
	if got != EXPECTED:
		push_error("TD1: seed for 2026-01-01 drifted: %d != %d" % [got, EXPECTED]); return false
	if RS.daily_seed_for("2026-01-01") == RS.daily_seed_for("2026-01-02"):
		push_error("TD1: distinct dates produced the same seed"); return false
	if RS.daily_seed_for("2026-07-14") != RS.daily_seed_for("2026-07-14"):
		push_error("TD1: same date produced different seeds"); return false
	return true
```

> On first green run, replace the `EXPECTED :=` line with the observed integer
> literal (e.g. `var EXPECTED := 123456789`) so the test truly pins the value
> instead of comparing the function to itself.

### 1c. Register the file in `scripts/sim/tests/run_tests.gd`

`run_tests.gd` loads a **hardcoded** list — an unregistered file silently never
runs. In `_initialize()`, after the existing four `_run_test_file(...)` calls:

```gdscript
	_run_test_file("res://scripts/sim/tests/test_daily.gd")
```

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → all existing tests still pass **and** TD1 passes (after pinning the literal).
- Launch the game: unchanged (DAILY unreachable).

### App state after Task 1
Seed function and DAILY identity exist and are tested. No gameplay change.

---

## Task 2 — Daily persistence data layer + tests (TD4/TD5)

**Goal:** The one-attempt-per-day store, as a pure path-injectable static
layer (unit-tested) plus thin `RunState` wrappers. Nothing calls the wrappers
yet, so the game is unchanged.

### 2a. `scripts/run_state.gd` — state + persistence API

1. Add members near `mode`/`session_high_scores`:

```gdscript
var daily_date: String = ""            # "YYYY-MM-DD" (UTC) while a daily run is active
const DAILY_SAVE_PATH := "user://daily.cfg"
```

2. Add the pure static layer. Fail-open: any load failure (missing/corrupt
   file) returns `{}`, so a bad store yields a fresh attempt, never a crash or
   a lockout.

```gdscript
static func read_daily_attempt(path: String, date: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	if not cfg.has_section(date):
		return {}
	return {
		"state": cfg.get_value(date, "state", ""),
		"score": int(cfg.get_value(date, "score", 0)),
		"round": int(cfg.get_value(date, "round", 0)),
	}

static func write_daily_attempt(path: String, date: String, state: String, score: int, round: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)   # ignore result: absent file just starts empty
	cfg.set_value(date, "state", state)
	cfg.set_value(date, "score", score)
	cfg.set_value(date, "round", round)
	cfg.save(path)
```

3. Add the instance wrappers (bind the real save path; `start`/`finish` write
   to `daily_date` — the run's own date — so a run crossing UTC midnight
   finalizes the attempt it started):

```gdscript
func has_daily_attempt(date: String) -> bool:
	return not read_daily_attempt(DAILY_SAVE_PATH, date).is_empty()

func start_daily_attempt() -> void:
	write_daily_attempt(DAILY_SAVE_PATH, daily_date, "started", 0, 0)
	print("[Daily] attempt started — %s" % daily_date)

func finish_daily_attempt(score: int, round: int) -> void:
	write_daily_attempt(DAILY_SAVE_PATH, daily_date, "done", score, round)
	print("[Daily] attempt done — %d pts, round %d" % [score, round])
```

### 2b. `scripts/sim/tests/test_daily.gd` — TD4/TD5

Use a **relative** scratch path (`user://` is unreliable headless; `./sim_results/`
is gitignored and dir-created, matching the results writer). Clean up after.

```gdscript
const _SCRATCH := "./sim_results/test_daily.cfg"

func _reset_scratch() -> void:
	DirAccess.make_dir_absolute("./sim_results")
	if FileAccess.file_exists(_SCRATCH):
		DirAccess.remove_absolute(_SCRATCH)

# TD4 - Persistence round-trips; an unwritten date reads empty.
func test_td4_persistence_round_trip() -> bool:
	_reset_scratch()
	if not RS.read_daily_attempt(_SCRATCH, "2026-07-14").is_empty():
		push_error("TD4: fresh store should be empty"); return false
	RS.write_daily_attempt(_SCRATCH, "2026-07-14", "started", 0, 0)
	var a := RS.read_daily_attempt(_SCRATCH, "2026-07-14")
	if a.get("state") != "started" or a.get("score") != 0:
		push_error("TD4: started read-back wrong: %s" % a); return false
	RS.write_daily_attempt(_SCRATCH, "2026-07-14", "done", 287, 5)
	var b := RS.read_daily_attempt(_SCRATCH, "2026-07-14")
	if b.get("state") != "done" or b.get("score") != 287 or b.get("round") != 5:
		push_error("TD4: done read-back wrong: %s" % b); return false
	if not RS.read_daily_attempt(_SCRATCH, "2026-07-15").is_empty():
		push_error("TD4: unwritten date should read empty"); return false
	_reset_scratch()
	return true

# TD5 - Missing/corrupt store fails open (empty, no crash).
func test_td5_corrupt_store_fails_open() -> bool:
	_reset_scratch()
	if not RS.read_daily_attempt("./sim_results/nope.cfg", "2026-07-14").is_empty():
		push_error("TD5: missing file should read empty"); return false
	var f := FileAccess.open(_SCRATCH, FileAccess.WRITE)
	f.store_string("\x00\x01 not a config {{{")
	f.close()
	if not RS.read_daily_attempt(_SCRATCH, "2026-07-14").is_empty():
		push_error("TD5: corrupt file should read empty"); return false
	_reset_scratch()
	return true
```

### Verify
- `run_tests.gd` → TD1, TD4, TD5 pass; everything else still green.
- Game unchanged (wrappers unused).

### App state after Task 2
Attempt store exists and is tested. No gameplay change.

---

## Task 3 — Share-text builder + goldens (TD2/TD3)

**Goal:** The shareable result string, as a static function on `run_state.gd`
(not the dialog script — that will be scene-coupled and untestable headless).
Tested; unused by the game yet.

### 3a. `scripts/run_state.gd` — `build_share_text`

```gdscript
static func build_share_text(date: String, score: int, rounds_cleared: int) -> String:
	var squares := ""
	for _i in rounds_cleared:
		squares += "🟩"
	squares += "🟥"    # the run always ends on one failed round
	return "ScrabbleRabble 95 — Daily %s\nScore %d · Round %d\n%s" % [
		date, score, rounds_cleared + 1, squares]
```

`Round` reported is `rounds_cleared + 1` (the round the player died on).
`rounds_cleared` comes from `RunState.history.size()` at call time (§4/§5 of
the spec).

### 3b. `scripts/sim/tests/test_daily.gd` — TD2/TD3

```gdscript
# TD2 - Exact share-string format for a normal run.
func test_td2_share_text_golden() -> bool:
	var got := RS.build_share_text("2026-07-14", 287, 4)
	var want := "ScrabbleRabble 95 — Daily 2026-07-14\nScore 287 · Round 5\n🟩🟩🟩🟩🟥"
	if got != want:
		push_error("TD2: share text mismatch:\n got: %s\nwant: %s" % [got, want]); return false
	return true

# TD3 - Degenerate run: died in round 1, cleared nothing.
func test_td3_share_text_zero_rounds() -> bool:
	var got := RS.build_share_text("2026-07-14", 5, 0)
	if not got.ends_with("\n🟥"):
		push_error("TD3: zero-cleared should end with a single red square: %s" % got); return false
	if not (got.contains("Round 1") and got.contains("Score 5") and got.contains("2026-07-14")):
		push_error("TD3: missing score/round/date: %s" % got); return false
	return true
```

### Verify
- `run_tests.gd` → TD1–TD5 pass. (Emoji are UTF-8 string literals; GDScript
  handles them fine. If a console mangles display, the byte comparison still
  holds.)
- Game unchanged.

### App state after Task 3
Share string is defined and pinned. No gameplay change. **Tasks 1–3 together
deliver the full tested logic layer with zero runtime risk.**

---

## Task 4 — Seeded run RNG + `prepare_run()` wiring (game plays identically)

**Goal:** Introduce `RunState.rng` and seed it on every launch path, *before*
the first rack draw. Gameplay draws still use the global RNG (migrated in Task
5), so **behavior is unchanged** — the only visible effect is a new
`[RunState] run seed …` line each run. This is the scaffold the migration
lands on.

### 4a. `scripts/run_state.gd` — RNG + `prepare_run()`

1. Members:

```gdscript
var rng := RandomNumberGenerator.new()
var _run_prepared: bool = false
```

2. Command-line seed override (for the determinism check; parses the same way
   the sim runner does — `get_cmdline_user_args`, NOT `get_cmdline_args`):

```gdscript
func _forced_seed_arg() -> int:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--seed="):
			return int(raw.trim_prefix("--seed="))
	return 0
```

3. `prepare_run()` — seeds `rng`, records the daily attempt at launch (so
   quitting mid-run can't buy a retry), and logs the seed:

```gdscript
func prepare_run() -> void:
	_run_prepared = true
	var forced := _forced_seed_arg()
	if mode == Mode.DAILY:
		daily_date = Time.get_date_string_from_system(true)   # true = UTC
		rng.seed = forced if forced != 0 else daily_seed_for(daily_date)
		start_daily_attempt()
	else:
		daily_date = ""
		if forced != 0:
			rng.seed = forced
		else:
			rng.randomize()
	print("[RunState] run seed %d — %s%s" % [rng.seed, mode_name(), " (forced)" if forced != 0 else ""])
```

4. Fallback guard at the **top** of `reset()` (direct editor F6 launch skips
   the start screen; self-heal so the run is at least playable, and mark it
   non-canonical in the log):

```gdscript
func reset() -> void:
	if not _run_prepared:
		print("[RunState] prepare_run fallback — direct scene launch?")
		prepare_run()
	_run_prepared = false
	# ... existing reset body unchanged ...
```

`reset()` otherwise does **not** touch `rng`.

### 4b. Seed on every path into `main.tscn` — *before* the scene loads

`rack._ready()` draws the first 7 tiles before `main._ready()` runs (child
`_ready` first), so seeding must happen pre-scene-change. There are three
entry points (`git grep -n "reload_current_scene\|change_scene_to_file.*main"
scripts/`):

1. **`scripts/start_screen.gd::_on_mode_selected`** — after
   `RunState.mode = mode`, add:

```gdscript
	RunState.prepare_run()
```

2. **`scripts/game_over_dialog.gd::_on_restart`** — **replace** the
   `RunState.reset()` call with `RunState.prepare_run()`:

```gdscript
func _on_restart() -> void:
	print("[GameOverDialog] restart")
	RunState.prepare_run()
	get_tree().reload_current_scene()
```

Why replace, not add: on reload, `main._ready()` calls `reset()` anyway (which
resets round state). If `_on_restart` also called `reset()`, it would consume
`_run_prepared` and the reload's `reset()` would re-fallback and **re-seed
after** the rack already drew — a double-seed. Calling only `prepare_run()`
leaves `_run_prepared = true` for the reload's `reset()` to consume cleanly:
single seed, rack draws from it.

3. **`scripts/difficulty_end_dialog.gd::_on_restart`** — the same restart
   pattern for difficulty modes; apply the identical replacement
   (`RunState.reset()` → `RunState.prepare_run()` before
   `reload_current_scene()`). Not on the daily path, but it must stay
   single-seeded for consistency.

> Leave every `_on_quit()` (→ `start_screen.tscn`) as-is: it calls
> `RunState.reset()`, but the next run re-seeds through `_on_mode_selected`.

### Verify
- `run_tests.gd` → still green (no test touches `rng` yet).
- Launch each way (start-screen mode pick, game-over restart, difficulty-end
  restart): every run prints exactly one `[RunState] run seed N — <Mode>` and
  plays exactly as before. Direct F6 additionally prints the
  `prepare_run fallback` line.

### App state after Task 4
Every launch seeds `RunState.rng` before the first draw. Draws still use the
global RNG, so play is unchanged. Seed is observable in the log.

---

## Task 5 — RNG migration + observability logs (existing modes become deterministic)

**Goal:** Move every gameplay draw onto `RunState.rng` and add logs that make
each consumed draw observable. After this, `--seed=N` produces a fully
reproducible run in **every** mode, proven by a two-run log diff. This is the
correctness core of the feature.

### 5a. `scripts/rack.gd` — seeded draws + refill log

Both draw helpers:

```gdscript
	return bag[RunState.rng.randi() % bag.size()]   # in _draw_random_letter AND _draw_random_letter_excluding
```

At the end of `refill()` (after `_apply_modifiers()`), log the resulting rack
in slot order (`?` for a wildcard tile — new `[Rack]` prefix, a new subsystem):

```gdscript
	var slots := ""
	for t in tiles_in_hand:
		slots += "?" if t.modifier == GameData.MOD_WILD else t.letter
	print("[Rack] refill — %s" % slots)
```

Extend the existing discard log in `main.gd::discard_rack_tile` to name the
replacement letter (the incoming `new_tile` is in `result`):

```gdscript
	print("[Discard] rack discard — %s → %s, %d left" % [tile.letter, (result["new_tile"] as Tile).letter, RunState.discards_left])
```

### 5b. `scripts/board.gd::reroll_premiums` — seeded shuffle + position log

`Array.shuffle()` uses the global RNG. Replace it with the hand-rolled
Fisher–Yates already proven in `game_core.gd::_reroll_premiums`, driven by
`RunState.rng`, and log the actual placements:

```gdscript
	# Fisher-Yates on RunState.rng — Array.shuffle() is global-RNG-bound and
	# would break daily determinism (mirror of game_core.gd::_reroll_premiums).
	for i in range(positions.size() - 1, 0, -1):
		var j := RunState.rng.randi() % (i + 1)
		var tmp: Vector2i = positions[i]
		positions[i] = positions[j]
		positions[j] = tmp
	var i := 0
	var placed: Array[String] = []
	for prem in GameData.PREMIUM_COUNTS.keys():
		for _n in GameData.PREMIUM_COUNTS[prem]:
			var pos: Vector2i = positions[i]
			(cells[pos.x][pos.y] as BoardCell).set_premium(prem)
			placed.append("%s@(%d,%d)" % [prem, pos.x, pos.y])
			i += 1
	print("[Board] premiums rerolled — %s" % " ".join(placed))
```

(Delete the old `positions.shuffle()` line and the old count-only print.)

### 5c. `scripts/main.gd` — seeded upgrade rolls, offers log, autoplay seed, drop `randomize()`

1. `_roll_modifier`: `var r := RunState.rng.randi() % total`.
2. `_generate_upgrade_offers`: `var letter: String = pool[RunState.rng.randi() % pool.size()]`.
3. Log the rolled offers just before returning from `_generate_upgrade_offers`:

```gdscript
	var offer_strs: Array[String] = []
	for o in offers:
		offer_strs.append("%s×%s" % [o["letter"], o["modifier"]])
	print("[UpgradeWizard] offers — %s" % ", ".join(offer_strs))
	return offers
```

4. Delete `randomize()` from `_ready()` — the global RNG no longer feeds
   gameplay.
5. `_AutoplayAdapter._init`: seed its own RNG from the run stream so strategy
   tie-breaks (`word_search`/`hybrid` use `core.rng`) replay under `--seed`:

```gdscript
	rng = RandomNumberGenerator.new()
	rng.seed = RunState.rng.randi()
```

> **Leave `start_screen.gd::_set_random_subtitle`'s `pick_random()` alone** —
> it is cosmetic and runs before `prepare_run()`; routing it through the run
> RNG would consume draws and shift the seed stream.

### Verify
- **Audit grep** — the only survivors must be the subtitle and RNG member
  declarations:
  ```
  grep -rn "randi\|randf\|shuffle\|pick_random\|randomize" scripts/ --include="*.gd" \
    | grep -v "scripts/sim/" | grep -v "RunState.rng"
  ```
- `run_tests.gd` → still green (`game_core.gd` untouched; sim parity intact).
- **Live determinism diff (the core guarantee):**
  ```
  godot --headless --path . -- --autoplay=word_search --seed=42 > a.log 2>&1
  godot --headless --path . -- --autoplay=word_search --seed=42 > b.log 2>&1
  diff <(grep -E '^\[(RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn)\]' a.log) \
       <(grep -E '^\[(RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn)\]' b.log)
  ```
  Empty diff = migration complete. Any divergence names the guilty subsystem by
  its log prefix. Also run once with `--autoplay=discard_word_search` to
  exercise the discard-replacement draw path.
- If Godot can't run in this environment: hand-trace the audit-grep output
  against §2 of the spec and **state plainly the runtime checks were not
  executed** (CLAUDE.md harness rule); the diff becomes the pre-merge gate.

### App state after Task 5
All gameplay randomness is seeded. `--seed=N` reproduces any run in any mode.
DAILY is still unreachable, but the moment it is wired up it will be
deterministic for free.

---

## Task 6 — Daily mode reachable + one attempt/day (playable & deterministic)

**Goal:** Add the start-screen entry point and the loss-path finalize hook. Now
DAILY is fully playable, seed-deterministic (Task 5), and enforces one attempt
per UTC day. Game-over still shows the **standard** dialog (share card is Task
7).

### 6a. `scenes/start_screen.tscn` — the Daily button

Add a `DailyButton` node between `EndlessButton` and `QuitGap`, mirroring the
other menu buttons' properties:

```
[node name="DailyButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Daily"
```

### 6b. `scripts/start_screen.gd` — wire + gate the button

1. `@onready` ref beside the others:

```gdscript
@onready var daily_button: Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/DailyButton
```

2. In `_ready()`, connect it and set today's label/gate. Beside the other
   `pressed.connect` lines:

```gdscript
	daily_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.DAILY))
	_refresh_daily_button()
```

3. Add the gate helper — disabled with the result shown once today's attempt
   exists, so the day is spent whether the player finished or bailed:

```gdscript
func _refresh_daily_button() -> void:
	var today := Time.get_date_string_from_system(true)   # UTC, matches the seed
	var attempt := RunState.read_daily_attempt(RunState.DAILY_SAVE_PATH, today)
	if attempt.is_empty():
		daily_button.text = "Daily — %s" % today
		daily_button.disabled = false
	else:
		daily_button.text = "Daily — %d pts" % int(attempt.get("score", 0))
		daily_button.disabled = true
	print("[StartScreen] daily button — %s" % ("open" if not daily_button.disabled else "spent"))
```

4. In `_on_mode_selected`, add `daily_button.disabled = true` to the block that
   disables the other five buttons during the launch glitch.

> `_maybe_autoplay()` still launches `Mode.ENDLESS` — autoplay must never
> consume the day's attempt. Leave it unchanged.

### 6c. `scripts/run_state.gd` — finalize the attempt on the loss path

In `register_turn_score`, the endless-style loss branch (the `else` under
`elif turns_left <= 0`) must record the daily result **before** emitting
`game_over`, because the handler tears the scene down:

```gdscript
		else:
			is_game_over = true
			if mode == Mode.DAILY:
				finish_daily_attempt(total_score, current_round)
			print("[RunState] game over — round %d, scored %d / %d" % [current_round, round_score, target_score])
			game_over.emit(current_round, round_score, final_target())
```

> Keep the existing `game_over.emit(...)` arguments exactly as they are; only
> the `finish_daily_attempt` line is inserted. (`start_daily_attempt` already
> ran in `prepare_run` at launch, so a mid-run quit leaves a `started` record
> that still gates the button.)

### Verify
- `run_tests.gd` → green.
- Play a full daily: Start screen shows `Daily — <today>` → pick it → the
  `[RunState] run seed` line uses `daily_seed_for(today)` → lose the run →
  standard game-over dialog. Return to title (Quit) → the button now reads
  `Daily — N pts` and is disabled.
- Determinism: note the first `[Rack] refill` and `[Board] premiums rerolled`
  positions; delete `user://daily.cfg`; replay the same date → identical seed
  line, rack, and premium positions.
- Mid-run quit (title/X mid-game) → relaunch → button still disabled (attempt
  consumed at launch).

### App state after Task 6
Daily is a first-class, deterministic, one-per-day mode. Result surfaces on the
start-screen button. Game-over uses the standard dialog.

---

## Task 7 — Daily share dialog (replaces game-over for daily)

**Goal:** On a daily game-over, show a Win95 share card with a copyable result
string instead of the standard dialog.

### 7a. New scene `scenes/daily_share_dialog.tscn`

Duplicate `scenes/game_over_dialog.tscn`'s chrome (`WindowFrame` → `InnerVBox`
→ `TitleBar` with `-`/`O`/`X` → `BodyArea`). Point the root's `script` at
`scripts/daily_share_dialog.gd`, set the title label to `Daily Result`, and in
`BodyArea` provide:

- `DateLabel`, `ScoreLabel` (Labels, centered, mirroring the game-over dialog).
- `ShareText` — a `TextEdit` with `editable = false`, `custom_minimum_size =
  Vector2(300, 64)`, for the multi-line share string.
- `ButtonRow` (HBoxContainer, `alignment = 1`) with `CopyButton`
  (`theme_type_variation = &"PlayButton"`, the primary action, `text = "Copy
  Result"`) and `OkButton` (`text = "OK"`), matching the game-over button
  sizing (`custom_minimum_size = Vector2(88, 24)`).

### 7b. New file `scripts/daily_share_dialog.gd`

Scene-coupled (uses `$` paths) — this is why `build_share_text` lives in
`run_state.gd`, not here.

```gdscript
extends Panel

var _date: String = ""
var _score: int = 0
var _rounds_cleared: int = 0

func setup(date: String, score: int, rounds_cleared: int) -> void:
	_date = date
	_score = score
	_rounds_cleared = rounds_cleared

func _ready() -> void:
	$InnerVBox/BodyArea/DateLabel.text  = "Daily %s" % _date
	$InnerVBox/BodyArea/ScoreLabel.text = "Score %d · Round %d" % [_score, _rounds_cleared + 1]
	$InnerVBox/BodyArea/ShareText.text  = RunState.build_share_text(_date, _score, _rounds_cleared)
	$InnerVBox/BodyArea/ButtonRow/CopyButton.pressed.connect(_on_copy)
	$InnerVBox/BodyArea/ButtonRow/OkButton.pressed.connect(_on_quit)
	# Win95: the X closes the window → same as the cancel/OK path.
	$InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn.pressed.connect(_on_quit)
	$InnerVBox/BodyArea/ButtonRow/CopyButton.grab_focus()

func _on_copy() -> void:
	DisplayServer.clipboard_set($InnerVBox/BodyArea/ShareText.text)
	print("[Daily] result copied")

func _on_quit() -> void:
	print("[Daily] share dialog closed — returning to title")
	RunState.reset()
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
```

> `_on_quit` is named to match `game_over_dialog.gd` so the existing autoplay
> quit path (`_autoplay_quit_game_over` calls `dialog._on_quit()`) works
> unchanged when it lands on this dialog.

### 7c. `scripts/main.gd` — branch `_on_game_over` for daily

Add the preload beside the other scene consts:

```gdscript
const DAILY_SHARE_SCENE := preload("res://scenes/daily_share_dialog.tscn")
```

At the **top** of `_on_game_over`, before the standard dialog is built, divert
to the share dialog for daily runs — reusing the exact same layer/blocker/
centering scaffolding the standard path uses:

```gdscript
func _on_game_over(final_round: int, final_round_score: int, final_target: int) -> void:
	_autoplay_active = false
	_update_hud()
	var dialog: Panel
	if RunState.mode == RunState.Mode.DAILY:
		dialog = DAILY_SHARE_SCENE.instantiate()
		dialog.setup(RunState.daily_date, RunState.total_score, RunState.history.size())
	else:
		dialog = GAME_OVER_SCENE.instantiate()
		dialog.setup(final_round, final_round_score, final_target)
	var layer := CanvasLayer.new()
	layer.layer = 50   # below the CRT overlay (100)
	add_child(layer)
	var blocker := Control.new()
	blocker.name = "ModalBlocker"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(blocker)
	layer.add_child(dialog)
	var vp_size := get_viewport().get_visible_rect().size
	dialog.position = (vp_size - dialog.custom_minimum_size) / 2.0
	if _autoplay_strategy_arg() != "":
		RunState.autoplay_run_completed = true
		_autoplay_quit_game_over(dialog)
```

> This restructures the existing `_on_game_over` body (which currently only
> builds `GAME_OVER_SCENE`) — keep every line except the dialog construction,
> which now branches. `history.size()` is the rounds-cleared count (each
> `_advance_round` appends one).

### Verify
- `run_tests.gd` → green.
- Daily loss → the share card appears (not the standard game-over), showing
  date, `Score N · Round M`, and the 3-line string with the right green/red
  squares. **Copy Result** → paste elsewhere yields exactly
  `RunState.build_share_text(...)` (matches TD2's format). OK / X → title,
  button now spent.
- Endless/difficulty game-over still shows their normal dialogs (the branch is
  daily-only).
- `--autoplay` on a daily-seeded loss still self-quits (shared `_on_quit`).

### App state after Task 7
Daily has its own share-card ending with clipboard copy. Feature is
functionally complete.

---

## Task 8 — Docs (CLAUDE.md + sim README)

**Goal:** Record the new invariant so future work doesn't silently break the
daily.

### 8a. `CLAUDE.md`

- **"Game state"**: note `RunState` now owns the run RNG (`rng`, seeded in
  `prepare_run()`), lists the new `Mode.DAILY`, and add the rule: *"Gameplay
  randomness goes through `RunState.rng` — never global
  `randi()`/`shuffle()`/`pick_random()` in gameplay code (mirror of the sim's
  seeding rule). The only exemption is cosmetic pre-run randomness (the
  start-screen subtitle)."*
- Add a short **Daily mode** note: seed = `hash` of the UTC date, one attempt
  per day in `user://daily.cfg`, plays the Endless ruleset, share card on
  game-over.
- Add `[Rack]` and `[Daily]` to the structured-logging prefix list.

### 8b. `scripts/sim/README.md`

One line: the live game is now seeded through `RunState.rng` the same way the
sim seeds `GameCore.rng` (relevant to future live↔sim replay work for #21).

### Verify
- Re-read both docs; every claim matches the shipped code (enum, prefixes,
  save path, exemption).

### App state after Task 8
The RNG-seeding invariant is documented; the feature is done.

---

## Done criteria (all tasks)

- `run_tests.gd` reports all existing groups plus **TD1–TD5** passing;
  `game_core.gd` and all `TC*`/`TSM*` expectations are untouched.
- The audit grep (Task 5) shows no global gameplay RNG outside the start-screen
  subtitle and RNG member declarations.
- Two `--seed=42` autoplay runs produce an **empty diff** over the
  `[RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn]` log surface.
- Picking **Daily** plays a run seeded from the UTC date; the same date always
  yields the same first rack and premium layout.
- One attempt per UTC day is enforced locally (button gates on
  `user://daily.cfg`, attempt consumed at launch).
- A daily game-over shows the Win95 share card; **Copy Result** puts the exact
  `build_share_text` string on the clipboard; the summary reveals score/round
  but not the board.
- Non-daily modes are behaviorally unchanged.
```
