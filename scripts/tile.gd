# res://scripts/tile.gd
class_name Tile
extends Panel

@export var letter: String = "A"

@onready var letter_label: Label = $LetterLabel
@onready var point_label: Label  = $PointLabel

var location: String  = "rack"
var board_pos: Vector2i = Vector2i(-1, -1)

const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")

func _ready() -> void:
	_refresh_visual()
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_letter(new_letter: String) -> void:
	letter = new_letter.to_upper()
	if is_inside_tree():
		_refresh_visual()

func _refresh_visual() -> void:
	letter_label.text = letter
	point_label.text  = str(GameData.score_for_letter(letter))

func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	# Raised bevel: light top-left edges, dark bottom-right edges
	draw_line(Vector2(0, 0),   Vector2(w - 1, 0),   C_OUTER_LIGHT)
	draw_line(Vector2(0, 0),   Vector2(0, h - 1),   C_OUTER_LIGHT)
	draw_line(Vector2(1, 1),   Vector2(w - 2, 1),   C_INNER_LIGHT)
	draw_line(Vector2(1, 1),   Vector2(1, h - 2),   C_INNER_LIGHT)
	draw_line(Vector2(w - 2, 1), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(1, h - 2), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(w - 1, 0), Vector2(w - 1, h - 1), C_OUTER_DARK)
	draw_line(Vector2(0, h - 1), Vector2(w - 1, h - 1), C_OUTER_DARK)

# --- Drag and drop source ---
func _get_drag_data(_at_position: Vector2) -> Variant:
	if location == "board":
		return null
	var preview_root := Control.new()
	var preview := duplicate() as Control
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.position = -size / 2.0
	preview_root.add_child(preview)
	set_drag_preview(preview_root)
	return self
