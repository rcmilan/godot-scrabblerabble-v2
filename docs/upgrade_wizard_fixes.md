# Upgrade Wizard — Fix Tasks (visual rebuild)

> **Supersedes the earlier version of this file.** The wizard shipped
> (commits `a3c9ba8`…`164845e`) but renders broken: elements float over
> the board with no background, arrow keys look dead, the banner title
> flies off-screen, and `×2/×3` shows missing-glyph boxes.
>
> These tasks migrate the shipped code to the corrected spec in
> `docs/upgrade_wizard_design.md` ("The wizard dialog" section). Do them
> **in order**; each is small and self-contained. Implementations target
> a less-sophisticated agent (haiku): every change below is given as
> exact file content or exact old→new code. Do not improvise beyond it.

**Files touched:** `scenes/upgrade_dialog.tscn`,
`scripts/upgrade_dialog.gd`, `scripts/upgrade_item.gd`,
`scripts/main.gd`.

**Cannot run Godot in this environment** — there is no `godot` binary.
After each task, just confirm the file matches the snippet exactly and
that GDScript has no obvious syntax error. The human will run the game.

**Do NOT touch** offer generation (`_generate_upgrade_offers`), the
auto-pick heuristic, or the sim (`game_core.gd`, tests). None of these
tasks change game logic, so TSM10/TSM11 and autoplay must be unaffected.

---

## Task 1 — Rebuild the dialog as a container-based modal

**Why:** a bare `Panel` is not a container, so it never grew to wrap its
children — content overflowed the painted gray and rendered over the
board. Switching to `PanelContainer` (paints the frame **and** sizes to
content) inside a `CenterContainer` (auto-centers) fixes the background
and the centering at once. The scene's root becomes the full-screen
input blocker, so `main.gd` stops building one.

### 1a. Replace `scenes/upgrade_dialog.tscn` with exactly this

```
[gd_scene load_steps=2 format=3 uid="uid://upgrade_dialog01"]

[ext_resource type="Script" path="res://scripts/upgrade_dialog.gd" id="1"]

[node name="ModalRoot" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 0
script = ExtResource("1")

[node name="CenterContainer" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Window" type="PanelContainer" parent="CenterContainer"]
layout_mode = 2
custom_minimum_size = Vector2(420, 360)
theme_type_variation = &"WindowFrame"

[node name="RootVBox" type="VBoxContainer" parent="CenterContainer/Window"]
layout_mode = 2

[node name="TitleBar" type="Panel" parent="CenterContainer/Window/RootVBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 22)
theme_type_variation = &"TitleBar"

[node name="TitleContent" type="HBoxContainer" parent="CenterContainer/Window/RootVBox/TitleBar"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
offset_left = 4.0
offset_right = -2.0

[node name="TitleLabel" type="Label" parent="CenterContainer/Window/RootVBox/TitleBar/TitleContent"]
layout_mode = 2
size_flags_horizontal = 3
text = "Upgrade Wizard"
theme_override_colors/font_color = Color(1, 1, 1, 1)

[node name="WinButtons" type="HBoxContainer" parent="CenterContainer/Window/RootVBox/TitleBar/TitleContent"]
layout_mode = 2
size_flags_horizontal = 8
separation = 2

[node name="CloseBtn" type="Button" parent="CenterContainer/Window/RootVBox/TitleBar/TitleContent/WinButtons"]
layout_mode = 2
custom_minimum_size = Vector2(16, 14)
focus_mode = 0
text = "X"

[node name="BodyArea" type="HBoxContainer" parent="CenterContainer/Window/RootVBox"]
layout_mode = 2
size_flags_vertical = 3

[node name="Banner" type="Control" parent="CenterContainer/Window/RootVBox/BodyArea"]
layout_mode = 2
custom_minimum_size = Vector2(96, 0)
size_flags_vertical = 3
mouse_filter = 2

[node name="BodyMargin" type="MarginContainer" parent="CenterContainer/Window/RootVBox/BodyArea"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/margin_left = 10
theme_override_constants/margin_top = 10
theme_override_constants/margin_right = 10
theme_override_constants/margin_bottom = 10

[node name="ContentVBox" type="VBoxContainer" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 8

[node name="HeaderLabel" type="Label" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox"]
layout_mode = 2
text = "Choose an upgrade to install:"
theme_override_colors/font_color = Color(0, 0, 0.5019, 1)

[node name="Grid" type="GridContainer" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox"]
layout_mode = 2
size_flags_horizontal = 4
custom_minimum_size = Vector2(188, 204)
columns = 2
theme_override_constants/h_separation = 12
theme_override_constants/v_separation = 12

[node name="Caption" type="Label" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 32)
text = "Every A tile scores double points for the rest of the run."
autowrap_mode = 3

[node name="ButtonRow" type="HBoxContainer" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox"]
layout_mode = 2
alignment = 2
theme_override_constants/separation = 8

[node name="BackButton" type="Button" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(88, 24)
disabled = true
focus_mode = 0
text = "< Back"

[node name="NextButton" type="Button" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(88, 24)
text = "Next >"

[node name="CancelButton" type="Button" parent="CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow"]
layout_mode = 2
custom_minimum_size = Vector2(88, 24)
text = "Cancel"
```

### 1b. Update the top of `scripts/upgrade_dialog.gd`

The script now lives on a `Control` root (was `Panel`), and the node
paths are one level deeper. Replace the class line, `extends`, and the
seven `@onready` vars with:

```gdscript
class_name UpgradeDialog
extends Control

@onready var _grid:       GridContainer = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/Grid
@onready var _caption:    Label         = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/Caption
@onready var _banner:     Control       = $CenterContainer/Window/RootVBox/BodyArea/Banner
@onready var _back_btn:   Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/BackButton
@onready var _next_btn:   Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/NextButton
@onready var _cancel_btn: Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/CancelButton
@onready var _close_btn:  Button        = $CenterContainer/Window/RootVBox/TitleBar/TitleContent/WinButtons/CloseBtn
```

Leave the rest of `upgrade_dialog.gd` unchanged in this task (the
`_ready` body, `populate`, signal handlers all still work).

### 1c. Simplify `main.gd::_show_upgrade_dialog`

Replace lines 301–316 (the `var dialog … dialog.position = …` block,
i.e. the typed-`Panel` line, the blocker creation, and the centering
math) with:

```gdscript
	var dialog: UpgradeDialog = UPGRADE_DIALOG_SCENE.instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(dialog)
```

Keep everything after it (`dialog.populate(offers)`,
`dialog.focus_first()`, the `upgrade_picked`/`skipped` connections, the
autoplay call) exactly as-is.

**Result after Task 1:** the dialog is centered, the gray frame covers
every element (header, cards, caption, buttons), and clicks outside it
are blocked. Cards may still look slightly off until Tasks 2–6.

---

## Task 2 — Grid: exactly 2 columns

**Why:** `populate` overrides the scene's `columns = 2` with leftover
`ceil(sqrt(count))` logic. The wizard is a fixed 2-column grid.

In `scripts/upgrade_dialog.gd::populate`, replace:

```gdscript
	_grid.columns = max(1, int(ceil(sqrt(float(count)))))
```

with:

```gdscript
	_grid.columns = 2
```

(Leave everything else in `populate` alone.)

---

## Task 3 — Banner: readable gradient + in-code title

**Why:** the gradient lerps navy→pure-black (a dead void), and there is
no banner title anymore (the old rotated `Label` node was removed in
Task 1's scene). Draw both in the banner's draw callback.

Replace the whole `_on_banner_draw` function in
`scripts/upgrade_dialog.gd` with:

```gdscript
func _on_banner_draw() -> void:
	var banner_rect := _banner.get_rect()
	var steps := int(banner_rect.size.y)
	var navy := Color(0, 0, 0.5019, 1.0)
	var deep := Color(0, 0, 0.20, 1.0)
	for i in steps:
		var t := float(i) / float(max(1, steps - 1))
		_banner.draw_rect(Rect2(0, i, banner_rect.size.x, 1), navy.lerp(deep, t))

	var font := _banner.get_theme_default_font()
	if font:
		var text := "ScrabbleRabble 95"
		var font_size := 16
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var centre := banner_rect.size * 0.5
		_banner.draw_set_transform(centre, -PI / 2.0, Vector2.ONE)
		_banner.draw_string(font, Vector2(-text_w * 0.5, 0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 1))
		_banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

---

## Task 4 — ASCII `2x` / `3x` (the missing-glyph fix)

**Why:** `fonts/w95fa.otf` has no `×` (U+00D7); it renders as a box.

In `scripts/upgrade_item.gd::_draw`, replace:

```gdscript
		var mod_text := "×2" if modifier == GameData.MOD_2X else "×3"
```

with:

```gdscript
		var mod_text := "2x" if modifier == GameData.MOD_2X else "3x"
```

---

## Task 5 — Selection follows focus (the "arrow keys are dead" fix)

**Why:** the yellow border + caption are driven by `is_selected`, which
only changed on a mouse click. Arrow keys moved focus but nothing
redrew, so navigation looked dead. Make focus drive selection.

In `scripts/upgrade_item.gd::_ready`, replace:

```gdscript
	focus_entered.connect(queue_redraw)
```

with:

```gdscript
	focus_entered.connect(emit_selected)
```

(`emit_selected()` already exists and emits `selected(item_index)`,
which the dialog handles by updating every card's `is_selected`,
redrawing, and refreshing the caption. Leave `focus_exited` as-is.)

---

## Task 6 — 2D arrow navigation + button bridge

**Why:** with a 2-column grid, arrows must move in 2D and reach the
buttons. Replace the old 1-D nav wiring and handlers.

### 6a. In `scripts/upgrade_dialog.gd::populate`, replace the nav-wiring loop

Replace:

```gdscript
	# Wire navigation
	for i in _item_nodes.size():
		var item := _item_nodes[i]
		var captured_i := i
		item.nav_left.connect(func(): _on_item_nav_left(captured_i))
		item.nav_right.connect(func(): _on_item_nav_right(captured_i))
		item.nav_up.connect(func(): _next_btn.grab_focus())
		item.nav_down.connect(func(): _next_btn.grab_focus())
```

with:

```gdscript
	# Wire navigation (2-column grid)
	for i in _item_nodes.size():
		var captured_i := i
		_item_nodes[i].nav_left.connect(func(): _nav_horizontal(captured_i, -1))
		_item_nodes[i].nav_right.connect(func(): _nav_horizontal(captured_i, 1))
		_item_nodes[i].nav_up.connect(func(): _nav_vertical(captured_i, -1))
		_item_nodes[i].nav_down.connect(func(): _nav_vertical(captured_i, 1))
```

### 6b. Replace the two old nav handlers

Replace:

```gdscript
func _on_item_nav_left(i: int) -> void:
	if i > 0:
		_item_nodes[i - 1].grab_focus()

func _on_item_nav_right(i: int) -> void:
	if i < _item_nodes.size() - 1:
		_item_nodes[i + 1].grab_focus()
```

with:

```gdscript
const GRID_COLUMNS := 2

func _nav_horizontal(from_index: int, delta: int) -> void:
	var new_col := (from_index % GRID_COLUMNS) + delta
	if new_col < 0 or new_col >= GRID_COLUMNS:
		return
	var target := from_index + delta
	if target >= 0 and target < _item_nodes.size():
		_item_nodes[target].grab_focus()

func _nav_vertical(from_index: int, delta_rows: int) -> void:
	var target := from_index + delta_rows * GRID_COLUMNS
	if target >= 0 and target < _item_nodes.size():
		_item_nodes[target].grab_focus()
	elif delta_rows > 0:
		_next_btn.grab_focus()
```

### 6c. Let Up from the Next button return to the grid

In `scripts/upgrade_dialog.gd::_ready`, add one connection (after the
existing `_next_btn.pressed.connect(...)` line):

```gdscript
	_next_btn.gui_input.connect(_on_next_btn_gui_input)
```

and add this handler anywhere in the file:

```gdscript
func _on_next_btn_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		if _selected_index >= 0 and _selected_index < _item_nodes.size():
			_item_nodes[_selected_index].grab_focus()
		get_viewport().set_input_as_handled()
```

---

## Final manual check (human, with a window)

Reach an upgrade round (round 4, or temporarily set
`UPGRADE_EVERY_N_ROUNDS = 1` in `run_state.gd` — **revert before
committing**) and confirm:

1. The dialog is centered; the **gray frame covers every element** —
   no board visible behind the header, caption, or buttons.
2. Cards sit in a **2-column grid** (3 offers → two on top, one
   bottom-left). With 1/2/4 offers the caption and buttons stay put.
3. **Arrow keys move the yellow selection** in 2D and the caption
   updates live. Down from the bottom row reaches **Next**; Up from
   Next returns to the grid. Enter confirms; double-click confirms.
4. The banner is a **navy gradient** with "ScrabbleRabble 95" reading
   bottom-to-top **inside** it — nothing over the board.
5. Cards show **"2x" / "3x"** cleanly (no missing-glyph box).
6. Board/rack inert behind the modal; Cancel and the title-bar X skip.

## Suggested commits (one per task, or group as you prefer)

- `fix: rebuild upgrade wizard as container-based modal`
- `fix: upgrade grid fixed to 2 columns`
- `fix: upgrade banner gradient + in-code title`
- `fix: ASCII 2x/3x on upgrade cards (w95fa lacks ×)`
- `fix: upgrade selection follows focus`
- `fix: 2D upgrade navigation + button bridge`
