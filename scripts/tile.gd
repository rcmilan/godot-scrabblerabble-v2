# res://scripts/tile.gd
class_name Tile
extends Panel

@export var letter:   String = "A"
@export var modifier: String = ""

@onready var letter_label: Label = $LetterLabel
@onready var point_label:  Label  = $PointLabel

var location:  String   = "rack"
var board_pos: Vector2i = Vector2i(-1, -1)

const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")

const C_MOD_GRADIENT_LEFT    := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT   := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)
const C_MOD3X_GRADIENT_LEFT  := Color(0.0,         0.376, 0.0,   1.0)
const C_MOD3X_GRADIENT_RIGHT := Color(0.188,        0.753, 0.188, 1.0)
const C_LABEL_MOD            := Color(1.0, 1.0, 1.0, 1.0)
const C_LABEL_LETTER         := Color(0.0, 0.0, 0.502, 1.0)
const C_LABEL_POINT          := Color(0.251, 0.251, 0.251, 1.0)

func _ready() -> void:
	_refresh_visual()
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_letter(new_letter: String) -> void:
	letter = new_letter.to_upper()
	if is_inside_tree():
		_refresh_visual()

func set_modifier(value: String) -> void:
	modifier = value
	if is_inside_tree():
		_refresh_visual()
		queue_redraw()

func _refresh_visual() -> void:
	letter_label.text = letter
	point_label.text  = str(GameData.score_for_letter(letter))
	if modifier == GameData.MOD_2X or modifier == GameData.MOD_3X:
		letter_label.add_theme_color_override("font_color", C_LABEL_MOD)
		point_label.add_theme_color_override("font_color", C_LABEL_MOD)
	else:
		letter_label.add_theme_color_override("font_color", C_LABEL_LETTER)
		point_label.add_theme_color_override("font_color", C_LABEL_POINT)

func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	if modifier == GameData.MOD_2X:
		_draw_horizontal_gradient(Rect2(1, 1, w - 2, h - 2),
			C_MOD_GRADIENT_LEFT, C_MOD_GRADIENT_RIGHT)
	elif modifier == GameData.MOD_3X:
		_draw_horizontal_gradient(Rect2(1, 1, w - 2, h - 2),
			C_MOD3X_GRADIENT_LEFT, C_MOD3X_GRADIENT_RIGHT)
	# Raised bevel: light top-left edges, dark bottom-right edges
	draw_line(Vector2(0, 0),     Vector2(w - 1, 0),     C_OUTER_LIGHT)
	draw_line(Vector2(0, 0),     Vector2(0, h - 1),     C_OUTER_LIGHT)
	draw_line(Vector2(1, 1),     Vector2(w - 2, 1),     C_INNER_LIGHT)
	draw_line(Vector2(1, 1),     Vector2(1, h - 2),     C_INNER_LIGHT)
	draw_line(Vector2(w - 2, 1), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(1, h - 2), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(w - 1, 0), Vector2(w - 1, h - 1), C_OUTER_DARK)
	draw_line(Vector2(0, h - 1), Vector2(w - 1, h - 1), C_OUTER_DARK)

func _draw_horizontal_gradient(rect: Rect2, c0: Color, c1: Color) -> void:
	var steps: int = int(rect.size.x)
	for i in steps:
		var t: float = float(i) / float(max(1, steps - 1))
		var c: Color = c0.lerp(c1, t)
		draw_rect(Rect2(rect.position.x + i, rect.position.y, 1.0, rect.size.y), c)

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
