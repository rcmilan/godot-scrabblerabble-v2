# Difficulty Modes & High Scores — Implementation Plan

Implements `docs/difficulty_modes_design.md`. Read that for the *why*;
this is the *what, in what order*. Built for a less-sophisticated agent
(haiku): each slice is small, leaves the game runnable, and gives exact
code or precise steps.

## How to work this file

- Do slices **in order**; commit after each. One commit per slice,
  `feat:`/`fix:` headline + 2–5 lines + the session footer.
- Conventions (CLAUDE.md): tabs in GDScript; snake_case; log state
  transitions with the existing prefixes (`[RunState]`, `[StartScreen]`,
  new `[DifficultyEndDialog]`); project theme is the default (use
  `theme_type_variation`, don't set `theme`); no comments that restate
  code.
- **No `godot` binary here** — the human runs the game and the sim tests.
  After slices 1 and 5 the human runs:
  `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
- **Do NOT touch the simulator** (`game_core.gd`, `simulator.gd`,
  strategies, sim tests). Difficulty is **live-only**. The hard
  constraint: the **endless `RunState` path must stay byte-identical** —
  only *add* difficulty branches, never change the shared constants or
  the Fibonacci math.

## Confirmed code facts

- `RunState` (`scripts/run_state.gd`, autoload): `register_turn_score`
  (round_score += points; if ≥ target → `_advance_round` elif turns ≤ 0
  → `game_over`), `_advance_round` (Fib curve), `reset()`. Constants
  `TURNS_PER_ROUND=3, INITIAL_TILES_PER_TURN=4, INITIAL_TARGET_SCORE=20,
  UPGRADE_EVERY_N_ROUNDS=3, DISCARDS_PER_ROUND=3`.
- `main.gd`: `_ready` connects `RunState.round_won → _on_round_won` and
  `RunState.game_over → _on_game_over`; `_update_hud` at line ~378;
  `_on_game_over` instantiates `game_over_dialog` on a layer-50
  `CanvasLayer` + full-rect `mouse_filter=STOP` blocker, centered via
  `custom_minimum_size`; `_on_round_won` does the glitter burst
  (`GLITTER_SCENE`); `GLITTER_SCENE` preloaded.
- `game_over_dialog.gd/.tscn`: `setup(round, score, target)`; chrome is
  Panel(WindowFrame) → InnerVBox → TitleBar(Min/Max/Close) → BodyArea.
- `start_screen.gd/.tscn`: `TitleDialog` (360×220), `BodyArea` VBox with
  BigTitle/Subtitle/MidSpacer/`ButtonRow`(StartButton,Gap,QuitButton);
  `_on_start_pressed` → `_play_launch_glitch` → `_launch` (change scene
  to main); `_maybe_autoplay`.

---

## Slice 1 — `RunState` foundation (logic only)

**Goal:** add the mode model, total score, target tables, high-score
dict, and the `run_finished` path — endless stays byte-identical and
difficulty is dormant (not yet selectable).

All edits in `scripts/run_state.gd`.

### 1a. Add the enum, constants, signal, and vars

Near the top (after the existing `const` block / signals):

```gdscript
enum Mode { EASY, MEDIUM, HARD, ENDLESS }

const ROUNDS_PER_DIFFICULTY: int = 5
const DIFFICULTY_TARGETS := {
	Mode.EASY:   [12, 18, 26, 34, 44],
	Mode.MEDIUM: [16, 24, 34, 46, 60],
	Mode.HARD:   [25, 38, 52, 70, 92],
}
```
```gdscript
signal run_finished(won: bool, final_round: int, total: int)
```
With the other `var`s:
```gdscript
var mode: int = Mode.ENDLESS
var total_score: int = 0
var session_high_scores := { Mode.EASY: 0, Mode.MEDIUM: 0, Mode.HARD: 0 }
```

### 1b. Add helpers

```gdscript
func is_difficulty_mode() -> bool:
	return mode != Mode.ENDLESS

func mode_name() -> String:
	match mode:
		Mode.EASY:   return "Easy"
		Mode.MEDIUM: return "Medium"
		Mode.HARD:   return "Hard"
		_:           return "Endless"

func record_high_score(total: int) -> bool:
	if not is_difficulty_mode():
		return false
	var prev: int = session_high_scores[mode]
	var is_new := total > prev
	if is_new:
		session_high_scores[mode] = total
	return is_new

func _finish_run(won: bool) -> void:
	is_game_over = true
	print("[RunState] run finished — %s, round %d, total %d" % [
		"won" if won else "lost", current_round, total_score])
	run_finished.emit(won, current_round, total_score)
```

### 1c. `reset()` — add total, mode-aware target; keep mode + high scores

Add `total_score = 0` alongside the other resets, and replace the single
`target_score = INITIAL_TARGET_SCORE` line with a mode branch:

```gdscript
	if is_difficulty_mode():
		target_score = DIFFICULTY_TARGETS[mode][0]
	else:
		target_score = INITIAL_TARGET_SCORE
```

Do **not** reset `mode` or `session_high_scores`. (Optionally update the
reset print to include `mode_name()`.)

### 1d. `register_turn_score()` — total + win-cap + difficulty loss

```gdscript
func register_turn_score(points: int) -> void:
	total_score += points
	round_score += points
	turns_left  -= 1
	round_score_changed.emit(round_score, target_score)
	turns_left_changed.emit(turns_left)
	if round_score >= target_score:
		if is_difficulty_mode() and current_round >= ROUNDS_PER_DIFFICULTY:
			_finish_run(true)
		else:
			_advance_round()
	elif turns_left <= 0:
		if is_difficulty_mode():
			_finish_run(false)
		else:
			is_game_over = true
			print("[RunState] game over — round %d, scored %d / %d" % [
				current_round, round_score, target_score])
			game_over.emit(current_round, round_score, target_score)
```

### 1e. `_advance_round()` — difficulty target branch only

Wrap the existing target computation in an `is_difficulty_mode()` branch;
leave the endless `current_round == 2` / Fib `else` branches **exactly as
they are**:

```gdscript
	if is_difficulty_mode():
		target_score = DIFFICULTY_TARGETS[mode][current_round - 1]
	elif current_round == 2:
		_t_prev      = _t_curr
		_t_curr      = 30.0
		target_score = 30
	else:
		var next := _t_curr + _t_prev / 2.0
		_t_prev      = _t_curr
		_t_curr      = next
		target_score = int(next)
```

(In difficulty mode the win-cap stops advancement at round 5, so
`current_round` is 2–5 here and the table index 1–4 is always valid.)

### Verify slice 1

1. Endless plays exactly as before (mode defaults to `ENDLESS`).
2. `run_tests.gd` — all TC/TS/TSM pass (game_core untouched; this
   confirms no shared-constant drift).

Commit slice 1.

---

## Slice 2 — `difficulty_end_dialog` scene + script

**Goal:** build the end popup standalone (not shown yet).

### 2a. `scenes/difficulty_end_dialog.tscn`

```
[gd_scene load_steps=2 format=3 uid="uid://b8diffenddlg01"]

[ext_resource type="Script" path="res://scripts/difficulty_end_dialog.gd" id="1"]

[node name="DifficultyEndDialog" type="Panel"]
custom_minimum_size = Vector2(340, 230)
size = Vector2(340, 230)
theme_type_variation = &"WindowFrame"
script = ExtResource("1")

[node name="InnerVBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 2.0
offset_top = 2.0
offset_right = -2.0
offset_bottom = -2.0
grow_horizontal = 2
grow_vertical = 2

[node name="TitleBar" type="Panel" parent="InnerVBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 22)
theme_type_variation = &"TitleBar"

[node name="TitleContent" type="HBoxContainer" parent="InnerVBox/TitleBar"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
offset_left = 4.0
offset_right = -2.0

[node name="TitleLabel" type="Label" parent="InnerVBox/TitleBar/TitleContent"]
layout_mode = 2
size_flags_horizontal = 3
text = "You Win!"
theme_override_colors/font_color = Color(1, 1, 1, 1)

[node name="WinButtons" type="HBoxContainer" parent="InnerVBox/TitleBar/TitleContent"]
layout_mode = 2
size_flags_horizontal = 8
separation = 2

[node name="MinBtn" type="Button" parent="InnerVBox/TitleBar/TitleContent/WinButtons"]
layout_mode = 2
custom_minimum_size = Vector2(16, 14)
focus_mode = 0
text = "-"

[node name="MaxBtn" type="Button" parent="InnerVBox/TitleBar/TitleContent/WinButtons"]
layout_mode = 2
custom_minimum_size = Vector2(16, 14)
focus_mode = 0
text = "O"

[node name="CloseBtn" type="Button" parent="InnerVBox/TitleBar/TitleContent/WinButtons"]
layout_mode = 2
custom_minimum_size = Vector2(16, 14)
focus_mode = 0
text = "X"

[node name="BodyArea" type="VBoxContainer" parent="InnerVBox"]
layout_mode = 2
size_flags_vertical = 3
alignment = 1

[node name="TopSpacer" type="Control" parent="InnerVBox/BodyArea"]
layout_mode = 2
custom_minimum_size = Vector2(0, 8)

[node name="ResultLabel" type="Label" parent="InnerVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 3
horizontal_alignment = 1
text = ""

[node name="ScoreLabel" type="Label" parent="InnerVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 3
horizontal_alignment = 1
text = ""

[node name="BestLabel" type="Label" parent="InnerVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 3
horizontal_alignment = 1
text = ""

[node name="NewHighLabel" type="Label" parent="InnerVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 3
horizontal_alignment = 1
text = "★ NEW HIGH SCORE! ★"
theme_override_colors/font_color = Color(0, 0, 0.5019, 1)

[node name="MidSpacer" type="Control" parent="InnerVBox/BodyArea"]
layout_mode = 2
custom_minimum_size = Vector2(0, 12)

[node name="ButtonRow" type="HBoxContainer" parent="InnerVBox/BodyArea"]
layout_mode = 2
alignment = 1

[node name="PlayAgainButton" type="Button" parent="InnerVBox/BodyArea/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(96, 24)
text = "Play Again"

[node name="Gap" type="Control" parent="InnerVBox/BodyArea/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(12, 0)

[node name="MenuButton" type="Button" parent="InnerVBox/BodyArea/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(96, 24)
text = "Menu"

[node name="BottomSpacer" type="Control" parent="InnerVBox/BodyArea"]
layout_mode = 2
custom_minimum_size = Vector2(0, 8)
```

### 2b. `scripts/difficulty_end_dialog.gd`

```gdscript
extends Panel

var _won: bool = false
var _final_round: int = 0
var _total: int = 0
var _best: int = 0
var _is_new: bool = false

func setup(won: bool, final_round: int, total: int, best: int, is_new: bool) -> void:
	_won = won
	_final_round = final_round
	_total = total
	_best = best
	_is_new = is_new

func _ready() -> void:
	$InnerVBox/TitleBar/TitleContent/TitleLabel.text = "You Win!" if _won else "Game Over"
	$InnerVBox/BodyArea/ResultLabel.text = "You cleared all 5 rounds!" if _won else "Failed at round %d of 5" % _final_round
	$InnerVBox/BodyArea/ScoreLabel.text = "Score: %d" % _total
	$InnerVBox/BodyArea/BestLabel.text = "Best (%s): %d" % [RunState.mode_name(), _best]
	$InnerVBox/BodyArea/NewHighLabel.visible = _is_new
	$InnerVBox/BodyArea/ButtonRow/PlayAgainButton.pressed.connect(_on_play_again)
	$InnerVBox/BodyArea/ButtonRow/MenuButton.pressed.connect(_on_menu)
	$InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn.pressed.connect(_on_menu)
	$InnerVBox/BodyArea/ButtonRow/PlayAgainButton.grab_focus()

func _on_play_again() -> void:
	print("[DifficultyEndDialog] play again")
	RunState.reset()
	get_tree().reload_current_scene()

func _on_menu() -> void:
	print("[DifficultyEndDialog] menu")
	RunState.reset()
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
```

### Verify slice 2

Project still loads (the scene/script parse). Nothing shows it yet.

Commit slice 2.

---

## Slice 3 — `main.gd` integration (popup + HUD)

**Goal:** wire `run_finished` to the popup and update the HUD. Endless
behaviour is unchanged (it never fires `run_finished`).

### 3a. Preload + connect

Add near the other `preload`s:
```gdscript
const DIFFICULTY_END_SCENE := preload("res://scenes/difficulty_end_dialog.tscn")
```
In `_ready`, after the `RunState.game_over.connect(...)` line:
```gdscript
	RunState.run_finished.connect(_on_run_finished)
```

### 3b. The handler (mirrors `_on_game_over`)

```gdscript
func _on_run_finished(won: bool, final_round: int, total: int) -> void:
	_autoplay_active = false
	_update_hud()
	if won:
		var emitter: GPUParticles2D = GLITTER_SCENE.instantiate()
		add_child(emitter)
		emitter.global_position = board.global_position + board.size * 0.5
	var is_new := RunState.record_high_score(total)
	var best: int = RunState.session_high_scores[RunState.mode]
	var dialog := DIFFICULTY_END_SCENE.instantiate()
	dialog.setup(won, final_round, total, best, is_new)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var blocker := Control.new()
	blocker.name = "ModalBlocker"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(blocker)
	layer.add_child(dialog)
	var vp_size := get_viewport().get_visible_rect().size
	dialog.position = (vp_size - dialog.custom_minimum_size) / 2.0
```

### 3c. HUD

Replace `_update_hud`'s body with:

```gdscript
func _update_hud() -> void:
	var round_str: String
	if RunState.is_difficulty_mode():
		round_str = "Round %d / 5" % RunState.current_round
	else:
		round_str = "Round %d" % RunState.current_round
	score_label.text = "Total: %d  |  %s  |  %d / %d" % [
		RunState.total_score, round_str, RunState.round_score, RunState.target_score]
	tiles_left_label.text = "Turns left: %d  |  Tiles/turn: %d" % [
		RunState.turns_left, RunState.tiles_per_turn]
```

### Verify slice 3

1. Endless plays normally; HUD now reads `Total: N | Round M | a / b`.
2. `run_finished` still can't fire (mode is endless) — no regression.
   (Difficulty becomes reachable in slice 4.)

Commit slice 3.

---

## Slice 4 — Start screen 5-option menu

**Goal:** make the four modes selectable; difficulty is now fully
playable end-to-end. Autoplay launches Endless.

### 4a. `scenes/start_screen.tscn` — grow the dialog

In the `TitleDialog` node, change the vertical offsets and minimum size:

```
offset_top = -170.0
offset_bottom = 170.0
custom_minimum_size = Vector2(360, 340)
```

(Leave `offset_left = -180.0`, `offset_right = 180.0` as-is.)

### 4b. `scenes/start_screen.tscn` — vertical menu

Replace the entire `ButtonRow` block (the `ButtonRow` HBox and its
`StartButton`, `Gap`, `QuitButton` children) with a `MenuButtons` VBox.
Keep the `MidSpacer` above it untouched:

```
[node name="MenuButtons" type="VBoxContainer" parent="TitleDialog/InnerVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 4
theme_override_constants/separation = 6
alignment = 1

[node name="EasyButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Easy"

[node name="MediumButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Medium"

[node name="HardButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Hard"

[node name="EndlessButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Endless"

[node name="QuitGap" type="Control" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(0, 10)

[node name="QuitButton" type="Button" parent="TitleDialog/InnerVBox/BodyArea/MenuButtons"]
layout_mode = 2
custom_minimum_size = Vector2(120, 26)
text = "Quit"
```

### 4c. `scripts/start_screen.gd`

Replace the `@onready` button refs and the `_ready` wiring, add
`_on_mode_selected`, and point autoplay at Endless. Keep
`_set_random_subtitle`, `_play_launch_glitch`, `_launch`,
`_on_quit_pressed`, `_has_autoplay_arg` as they are.

Replace the old `start_button`/`quit_button` `@onready` lines with:
```gdscript
@onready var easy_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/EasyButton
@onready var medium_button:  Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/MediumButton
@onready var hard_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/HardButton
@onready var endless_button: Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/EndlessButton
@onready var quit_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/QuitButton
```

Replace the button `pressed.connect` lines and focus grab in `_ready`
with:
```gdscript
	easy_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.EASY))
	medium_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.MEDIUM))
	hard_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.HARD))
	endless_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.ENDLESS))
	quit_button.pressed.connect(_on_quit_pressed)
	close_btn.pressed.connect(_on_quit_pressed)
	easy_button.grab_focus()
```

Replace `_on_start_pressed` with:
```gdscript
func _on_mode_selected(mode: int) -> void:
	if _launching:
		return
	_launching = true
	easy_button.disabled = true
	medium_button.disabled = true
	hard_button.disabled = true
	endless_button.disabled = true
	quit_button.disabled = true
	RunState.mode = mode
	print("[StartScreen] mode selected — %s" % RunState.mode_name())
	_play_launch_glitch()
```

In `_maybe_autoplay`, replace the final two lines
(`print(... pressing Start)` + `_on_start_pressed()`) with:
```gdscript
	print("[StartScreen] autoplay detected — launching Endless")
	await get_tree().create_timer(0.3).timeout
	_on_mode_selected(RunState.Mode.ENDLESS)
```

### Verify slice 4 (human, with a window)

1. Start screen shows Easy / Medium / Hard / Endless / Quit; Up/Down +
   Enter navigate; mouse works.
2. **Easy:** play through — targets follow the Easy table; clearing
   round 5 shows "You Win!" with `Score`/`Best`/NEW HIGH SCORE!;
   missing a target shows "Game Over — Failed at round N of 5".
   Play Again restarts Easy; Menu returns to the start screen.
3. Play Easy twice — second run's popup shows the higher session best,
   and NEW HIGH SCORE! only when beaten.
4. **Endless** still runs unbounded with the Fib curve and the old
   `game_over_dialog`.
5. Autoplay: `--autoplay=word_search` still reaches gameplay and the
   loop completes (it now launches Endless).

Commit slice 4.

---

## Slice 5 — Sim README + regression

In `scripts/sim/README.md`:
- **Update the autoplay log contract** lines to the new wording:
  `[StartScreen] autoplay detected — launching Endless`, followed by
  `[StartScreen] mode selected — Endless`, then
  `[StartScreen] launching main scene`.
- Add a short **"Difficulty modes (live-only)"** note: Easy/Medium/Hard
  (target tables, 5-round cap, `run_finished`, `total_score`, session
  high scores) are live-only and intentionally NOT modeled in
  `game_core.gd`; the sim runs Endless only.

### Verify slice 5

`run_tests.gd` green. Commit slice 5. Push the branch.

---

## Out of scope (do NOT build)

Disk persistence of high scores (`ConfigFile`/`user://`), an Endless
high score / "rounds reached" metric, showing high scores on the start
screen, simulating difficulty modes in `game_core`, per-mode tuning of
non-target params (turns/tiles/discards), and player-name entry. See
the design doc's "Out of scope" section.
