# res://scripts/board_cell.gd
class_name BoardCell
extends Panel

signal cell_clicked(cell: BoardCell)
signal move_requested(dir: Vector2i)

@onready var label: Label = $Label

var grid_pos:       Vector2i = Vector2i.ZERO
var current_tile:   Tile     = null
var locked_letter:  String   = ""
var locked_modifier: String  = ""

const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")
const C_CURSOR      := Color("#00FFFF")
const C_BG_EMPTY    := Color("#C0C0C0")
const C_BG_TILE     := Color("#FFFFC0")
const CURSOR_PERIOD := 0.5

const C_MOD_GRADIENT_LEFT    := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT   := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)
const C_MOD3X_GRADIENT_LEFT  := Color(0.0,        0.376, 0.0,   1.0)
const C_MOD3X_GRADIENT_RIGHT := Color(0.188,       0.753, 0.188, 1.0)

var _cursor_visible := true
var _cursor_timer   := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		cell_clicked.emit(self)
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click yanks an unlocked tile back to the rack. Locked cells hold
		# locked_letter with no current_tile, so they're untouched.
		if current_tile != null:
			var main := get_tree().get_first_node_in_group("main")
			if main and main.has_method("on_tile_returned_to_rack"):
				main.on_tile_returned_to_rack(current_tile)
		accept_event()
		return
	if event.is_action_pressed("ui_left"):
		move_requested.emit(Vector2i(-1, 0)); accept_event()
	elif event.is_action_pressed("ui_right"):
		move_requested.emit(Vector2i(1, 0)); accept_event()
	elif event.is_action_pressed("ui_up"):
		move_requested.emit(Vector2i(0, -1)); accept_event()
	elif event.is_action_pressed("ui_down"):
		move_requested.emit(Vector2i(0, 1)); accept_event()

func _on_focus_entered() -> void:
	_cursor_timer = 0.0
	_cursor_visible = true
	queue_redraw()

func _on_focus_exited() -> void:
	_cursor_visible = true
	_cursor_timer = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not has_focus():
		return
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_PERIOD:
		_cursor_timer = 0.0
		_cursor_visible = !_cursor_visible
		queue_redraw()

func _draw() -> void:
	var w      := int(size.x)
	var h      := int(size.y)
	var filled := not is_empty()
	var active_mod := get_modifier()

	# Background
	if filled and active_mod == GameData.MOD_2X:
		_draw_horizontal_gradient(Rect2(0, 0, w, h), C_MOD_GRADIENT_LEFT, C_MOD_GRADIENT_RIGHT)
	elif filled and active_mod == GameData.MOD_3X:
		_draw_horizontal_gradient(Rect2(0, 0, w, h), C_MOD3X_GRADIENT_LEFT, C_MOD3X_GRADIENT_RIGHT)
	else:
		draw_rect(Rect2(0, 0, w, h), C_BG_TILE if filled else C_BG_EMPTY)

	if filled:
		# Raised bevel: light top-left, dark bottom-right (matches hand tile)
		draw_line(Vector2(0, 0),     Vector2(w - 1, 0),     C_OUTER_LIGHT)
		draw_line(Vector2(0, 0),     Vector2(0, h - 1),     C_OUTER_LIGHT)
		draw_line(Vector2(1, 1),     Vector2(w - 2, 1),     C_INNER_LIGHT)
		draw_line(Vector2(1, 1),     Vector2(1, h - 2),     C_INNER_LIGHT)
		draw_line(Vector2(w - 2, 1), Vector2(w - 2, h - 2), C_INNER_DARK)
		draw_line(Vector2(1, h - 2), Vector2(w - 2, h - 2), C_INNER_DARK)
		draw_line(Vector2(w - 1, 0), Vector2(w - 1, h - 1), C_OUTER_DARK)
		draw_line(Vector2(0, h - 1), Vector2(w - 1, h - 1), C_OUTER_DARK)
	else:
		# Sunken bevel: dark top-left, light bottom-right (empty cell)
		draw_line(Vector2(0, 0),     Vector2(w - 1, 0),     C_INNER_DARK)
		draw_line(Vector2(0, 0),     Vector2(0, h - 1),     C_INNER_DARK)
		draw_line(Vector2(1, 1),     Vector2(w - 2, 1),     C_OUTER_DARK)
		draw_line(Vector2(1, 1),     Vector2(1, h - 2),     C_OUTER_DARK)
		draw_line(Vector2(w - 2, 1), Vector2(w - 2, h - 2), C_INNER_LIGHT)
		draw_line(Vector2(1, h - 2), Vector2(w - 2, h - 2), C_INNER_LIGHT)
		draw_line(Vector2(w - 1, 0), Vector2(w - 1, h - 1), C_OUTER_LIGHT)
		draw_line(Vector2(0, h - 1), Vector2(w - 1, h - 1), C_OUTER_LIGHT)

	if has_focus():
		draw_rect(Rect2(0, 0, w, h),         C_CURSOR,     false)  # outer cyan ring
		draw_rect(Rect2(1, 1, w - 2, h - 2), C_OUTER_DARK, false)  # dark gap
		draw_rect(Rect2(2, 2, w - 4, h - 4), C_CURSOR,     false)  # inner cyan ring
		if _cursor_visible and is_empty():
			draw_rect(Rect2(size.x * 0.5 - 6.0, size.y - 7.0, 12.0, 2.0), C_CURSOR)

func _draw_horizontal_gradient(rect: Rect2, c0: Color, c1: Color) -> void:
	var steps: int = int(rect.size.x)
	for i in steps:
		var t: float = float(i) / float(max(1, steps - 1))
		var c: Color = c0.lerp(c1, t)
		draw_rect(Rect2(rect.position.x + i, rect.position.y, 1.0, rect.size.y), c)

func _sync_label_color() -> void:
	var mod := get_modifier()
	if mod == GameData.MOD_2X or mod == GameData.MOD_3X:
		label.add_theme_color_override("font_color", Color.WHITE)
	else:
		label.remove_theme_color_override("font_color")

func is_empty() -> bool:
	return current_tile == null and locked_letter == ""

func get_letter() -> String:
	if current_tile != null:
		return current_tile.letter
	return locked_letter

func get_modifier() -> String:
	if current_tile != null:
		return current_tile.modifier
	return locked_modifier

func place_tile(tile: Tile) -> void:
	current_tile = tile
	label.text = tile.letter
	tile.location = "board"
	tile.board_pos = grid_pos
	_sync_label_color()
	queue_redraw()
	_play_place_animation()

func _play_place_animation() -> void:
	pivot_offset = size / 2.0
	scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func clear_pending() -> void:
	current_tile = null
	if locked_letter == "":
		label.text = ""
	else:
		label.text = locked_letter
	_sync_label_color()
	queue_redraw()

func lock_pending() -> void:
	if current_tile != null:
		locked_letter = current_tile.letter
		locked_modifier = current_tile.modifier
		if current_tile.get_parent():
			current_tile.get_parent().remove_child(current_tile)
		current_tile.queue_free()
		current_tile = null
	_sync_label_color()
	queue_redraw()

func clear_all() -> void:
	if current_tile != null:
		if current_tile.get_parent():
			current_tile.get_parent().remove_child(current_tile)
		current_tile.queue_free()
		current_tile = null
	locked_letter   = ""
	locked_modifier = ""
	label.text      = ""
	_sync_label_color()
	queue_redraw()

# --- Drag and drop target ---
func _get_drag_data(_at_position: Vector2) -> Variant:
	if current_tile == null:
		return null  # empty or locked cell — nothing to pick up
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("can_move_board_tile") and not main.can_move_board_tile():
		return null
	var preview_root := Control.new()
	var preview := current_tile.duplicate() as Control
	preview.visible = true  # the source node is invisible; duplicate inherits that
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.position = -current_tile.size / 2.0
	preview_root.add_child(preview)
	set_drag_preview(preview_root)
	return current_tile

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Tile):
		return false
	var t := data as Tile
	if t.location == "board":
		if t.board_pos == grid_pos:
			return false           # dropping on its own cell — no-op
		return locked_letter == "" # empty -> move, unlocked -> swap, locked -> reject
	# rack-tile placement: empty cell AND under the per-turn placement cap
	if not is_empty():
		return false
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("can_place_pending_tile") and not main.can_place_pending_tile():
		return false
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var tile := data as Tile
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("on_tile_dropped_on_cell"):
		main.on_tile_dropped_on_cell(tile, self)
