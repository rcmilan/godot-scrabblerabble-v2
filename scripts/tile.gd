# res://scripts/tile.gd
class_name Tile
extends Panel

@export var letter: String = "A"

@onready var letter_label: Label = $LetterLabel
@onready var point_label: Label = $PointLabel

# Where this tile currently lives. Used by the rack/board to remove/return it.
# "rack" or "board". When on board, board_pos stores the (x,y) cell.
var location: String = "rack"
var board_pos: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	_refresh_visual()
	# We want to be a drag source AND clickable.
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_letter(new_letter: String) -> void:
	letter = new_letter.to_upper()
	if is_inside_tree():
		_refresh_visual()

func _refresh_visual() -> void:
	letter_label.text = letter
	point_label.text = str(GameData.score_for_letter(letter))

# --- Drag and drop source ---
func _get_drag_data(_at_position: Vector2) -> Variant:
	if location == "board":
		return null
	# Wrap the preview in a Control so we can offset it to be centered on cursor.
	var preview_root := Control.new()
	var preview := duplicate() as Control
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.position = -size / 2.0
	preview_root.add_child(preview)
	set_drag_preview(preview_root)
	return self
