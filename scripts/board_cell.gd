# res://scripts/board_cell.gd
class_name BoardCell
extends Panel

signal cell_clicked(cell: BoardCell)

@onready var label: Label = $Label

var grid_pos: Vector2i = Vector2i.ZERO
var current_tile: Tile = null
var locked_letter: String = ""

const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")
const C_CURSOR      := Color("#00FFFF")
const C_BG_EMPTY    := Color("#C0C0C0")
const C_BG_TILE     := Color("#FFFFC0")
const CURSOR_PERIOD := 0.5

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

	# Background — cream when occupied, gray when empty
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

func is_empty() -> bool:
	return current_tile == null and locked_letter == ""

func get_letter() -> String:
	if current_tile != null:
		return current_tile.letter
	return locked_letter

func place_tile(tile: Tile) -> void:
	current_tile = tile
	label.text = tile.letter
	tile.location = "board"
	tile.board_pos = grid_pos
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
	queue_redraw()

func lock_pending() -> void:
	if current_tile != null:
		locked_letter = current_tile.letter
		if current_tile.get_parent():
			current_tile.get_parent().remove_child(current_tile)
		current_tile.queue_free()
		current_tile = null
	queue_redraw()

func clear_all() -> void:
	if current_tile != null:
		if current_tile.get_parent():
			current_tile.get_parent().remove_child(current_tile)
		current_tile.queue_free()
		current_tile = null
	locked_letter = ""
	label.text    = ""
	queue_redraw()

# --- Drag and drop target ---
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Tile and is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var tile := data as Tile
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("on_tile_dropped_on_cell"):
		main.on_tile_dropped_on_cell(tile, self)
