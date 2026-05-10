# res://scripts/board_cell.gd
class_name BoardCell
extends Panel

signal cell_clicked(cell: BoardCell)

@onready var label: Label = $Label

var grid_pos: Vector2i = Vector2i.ZERO
# The tile placed THIS turn. null means empty (or fixed from prior turns).
var current_tile: Tile = null
# Letter committed in previous turns (locked, used for scoring chains).
var locked_letter: String = ""

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
	modulate = Color(1.2, 1.2, 0.6)  # highlight

func _on_focus_exited() -> void:
	modulate = Color(1, 1, 1)

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

func clear_pending() -> void:
	# Removes the "this turn" tile (used when undoing).
	current_tile = null
	if locked_letter == "":
		label.text = ""
	else:
		label.text = locked_letter

func lock_pending() -> void:
	if current_tile != null:
		locked_letter = current_tile.letter
		if current_tile.get_parent():
			current_tile.get_parent().remove_child(current_tile)
		current_tile.queue_free()
		current_tile = null

# --- Drag and drop target ---
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Tile and is_empty()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var tile := data as Tile
	# Tell the rack to release the tile (handled by Main).
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("on_tile_dropped_on_cell"):
		main.on_tile_dropped_on_cell(tile, self)
