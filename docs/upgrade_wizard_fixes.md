# Upgrade Wizard — Fix Task (embed the real Tile)

> The wizard layout, navigation, and banner are shipped and good. The
> only remaining issue: the offer card **redraws its own copy** of a
> tile in `upgrade_item.gd::_draw` (duplicated gradient/bevel/letter/
> point code). That duplicate has already drifted from the real tile
> once. This task removes the duplicate entirely and shows the **real
> `Tile`** (the exact node the rack/hand uses), so a tile is drawn by
> one piece of code everywhere.

**The rack is the standard.** `rack.gd` builds tiles by instancing
`res://scenes/tile.tscn` and calling `set_letter()` / `set_modifier()`.
The wizard card will do the same: instance a `Tile`, drop it in the
card, and add only the things a rack tile doesn't have — the "N in bag"
line and the yellow selection border.

**Only one file changes: `scripts/upgrade_item.gd`.** Do not touch
`upgrade_dialog.gd`, the scene, `main.gd`, `tile.gd`, the sim, or offer
generation. `upgrade_dialog.gd::populate` already sets `item_index`,
`letter`, `modifier`, and `is_selected` on each card before it is added
to the tree, and connects the `selected` / `confirmed` / `nav_*`
signals — all of which this new file still provides, so it stays
compatible with no edits.

No `godot` binary here; the human runs the game to verify.

---

## The task — replace the whole of `scripts/upgrade_item.gd`

Replace the **entire file** with exactly this:

```gdscript
class_name UpgradeItem
extends Control

signal selected(index: int)
signal confirmed(index: int)
signal nav_left
signal nav_right
signal nav_up
signal nav_down

const TILE_SCENE: PackedScene = preload("res://scenes/tile.tscn")
const BODY_SIZE := Vector2(56.0, 56.0)   # matches tile.tscn custom_minimum_size

const C_SELECTION_BORDER := Color(1.0, 1.0, 0.0, 1.0)
const C_BAG_COUNT        := Color(0.251, 0.251, 0.251, 1.0)

var item_index: int   = 0
var letter: String    = "A"
var modifier: String  = ""
var is_selected: bool = false

var _tile: Tile

func _ready() -> void:
	focus_mode          = FOCUS_ALL
	custom_minimum_size = Vector2(88.0, 96.0)
	mouse_filter        = MOUSE_FILTER_STOP
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	focus_entered.connect(emit_selected)
	focus_exited.connect(queue_redraw)
	_build_tile()

func _build_tile() -> void:
	# Reuse the real rack/board Tile so the wizard and the hand are always
	# drawn by the same code — tile.gd is the single source of truth.
	_tile = TILE_SCENE.instantiate() as Tile
	_tile.letter = letter
	_tile.position = Vector2((custom_minimum_size.x - BODY_SIZE.x) * 0.5, 0.0)
	add_child(_tile)
	_tile.set_modifier(modifier)
	# Neutralise the tile: the card must receive clicks, and the tile must
	# not be draggable inside the wizard.
	_tile.focus_mode   = Control.FOCUS_NONE
	_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in _tile.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	# The tile itself is a child node drawn on top; here we draw only the
	# selection ring (just outside the tile) and the "N in bag" line below.
	var tile_rect := Rect2(Vector2((size.x - BODY_SIZE.x) * 0.5, 0.0), BODY_SIZE)
	if is_selected:
		draw_rect(tile_rect.grow(2.0), C_SELECTION_BORDER, false, 2.0)
	var font := get_theme_default_font()
	if font:
		var bag_count: int = GameData.LETTER_DISTRIBUTION.get(letter, 0)
		var bag_text := "%d in bag" % bag_count
		var font_size_bag := 12
		var bag_size := font.get_string_size(bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_bag)
		var bag_pos := Vector2((size.x - bag_size.x) * 0.5, BODY_SIZE.y + 16.0)
		draw_string(font, bag_pos, bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_bag, C_BAG_COUNT)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		emit_confirmed()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			grab_focus()
			emit_selected()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed and mouse_event.double_click:
			emit_confirmed()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		nav_left.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		nav_right.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		nav_up.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		nav_down.emit()
		get_viewport().set_input_as_handled()

func emit_selected() -> void:
	selected.emit(item_index)

func emit_confirmed() -> void:
	confirmed.emit(item_index)
```

### What changed vs the old file (for your understanding only)

- **Deleted** all the tile-face drawing: the gradient/bevel/letter-color
  constants, the `_draw_mod2x_body` / `_draw_mod3x_body` /
  `_draw_win95_bevel` / `_draw_horizontal_gradient` helpers, and the
  letter/point/`2x`-text drawing in `_draw`.
- **Added** `_build_tile()`, which instances the real `Tile` and shows
  it — so the card now renders the letter, point value, gradient, and
  bevel through `tile.gd`, identical to the rack.
- **Kept** the selection ring and the (size-12) "N in bag" line, plus
  the whole `_gui_input` / signal surface unchanged.

---

## Manual check (human, with a window)

At an upgrade round, confirm:

1. Each offer tile looks **pixel-identical to a modifier tile in the
   rack** — same gradient, same white letter, same white point value in
   the bottom-right.
2. The yellow **selection ring** still hugs the focused/selected tile,
   and arrow keys / clicks still select; Enter / double-click confirm.
3. The **"N in bag"** line sits below each tile.
4. You **cannot drag** a wizard tile, and clicking a tile still selects
   its card.
5. Change something on the rack tile later (e.g. in `tile.gd`) and it
   shows up in the wizard automatically — that's the point.

## Suggested commit

- `fix: wizard shows real Tile instances instead of redrawing them`
