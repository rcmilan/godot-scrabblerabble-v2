class_name LetterItem
extends Control

signal pick_requested(index: int)
signal nav_left
signal nav_right
signal nav_up
signal nav_down

# Match tile.tscn custom_minimum_size = Vector2(56, 56)
const BODY_SIZE := Vector2(56.0, 56.0)

# Win95 bevel colors — identical to tile.gd
const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")

# Label colors — identical to tile.gd (non-modifier variant)
const C_LABEL_LETTER := Color(0.0,   0.0,   0.502, 1.0)
const C_LABEL_POINT  := Color(0.251, 0.251, 0.251, 1.0)

const C_FOCUS_BORDER := Color(1.0, 1.0, 0.0, 1.0)

const LETTER_POINTS_FALLBACK := {
	"A":1,"B":3,"C":3,"D":2,"E":1,"F":4,"G":2,"H":4,"I":1,"J":8,
	"K":5,"L":1,"M":3,"N":1,"O":1,"P":3,"Q":10,"R":1,"S":1,"T":1,
	"U":1,"V":4,"W":4,"X":8,"Y":4,"Z":10
}

var item_index: int = 0
var _letter: String = "A"
var _points: int = 1

func set_letter(letter: String) -> void:
	_letter = letter
	_points = LETTER_POINTS_FALLBACK.get(letter, 0)
	custom_minimum_size = BODY_SIZE
	queue_redraw()

func _ready() -> void:
	focus_mode = FOCUS_ALL
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	mouse_filter = MOUSE_FILTER_STOP
	for child in get_children():
		if child is Control:
			(child as Control).focus_mode = FOCUS_NONE
			(child as Control).mouse_filter = MOUSE_FILTER_IGNORE
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	custom_minimum_size = BODY_SIZE

func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	if w < 4 or h < 4:
		return

	# Centered 56x56 body rect
	var body_x := (size.x - BODY_SIZE.x) * 0.5
	var body_y := 0.0  # Full height
	var body_rect := Rect2(Vector2(body_x, body_y), BODY_SIZE)

	# Win95 raised bevel — same lines as tile.gd _draw()
	draw_line(Vector2(0, 0),     Vector2(w - 1, 0),     C_OUTER_LIGHT)
	draw_line(Vector2(0, 0),     Vector2(0, h - 1),     C_OUTER_LIGHT)
	draw_line(Vector2(1, 1),     Vector2(w - 2, 1),     C_INNER_LIGHT)
	draw_line(Vector2(1, 1),     Vector2(1, h - 2),     C_INNER_LIGHT)
	draw_line(Vector2(w - 2, 1), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(1, h - 2), Vector2(w - 2, h - 2), C_INNER_DARK)
	draw_line(Vector2(w - 1, 0), Vector2(w - 1, h - 1), C_OUTER_DARK)
	draw_line(Vector2(0, h - 1), Vector2(w - 1, h - 1), C_OUTER_DARK)

	var font := get_theme_default_font()
	if font:
		# Letter: font_size 24, centered — mirrors LetterLabel in tile.tscn
		var font_size_letter := 24
		var letter_size := font.get_string_size(_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_letter)
		var letter_pos := Vector2((size.x - letter_size.x) * 0.5,
				(size.y + letter_size.y) * 0.5 - 4.0)
		draw_string(font, letter_pos, _letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_letter, C_LABEL_LETTER)

		# Point value: font_size 9, bottom-right corner — mirrors PointLabel in tile.tscn
		var font_size_pts := 9
		var pts_str := str(_points)
		var pts_size := font.get_string_size(pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_pts)
		var pts_pos := Vector2(size.x - pts_size.x - 3.0, size.y - 3.0)
		draw_string(font, pts_pos, pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_pts, C_LABEL_POINT)

	if has_focus():
		draw_rect(body_rect.grow(2.0), C_FOCUS_BORDER, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		pick_requested.emit(item_index)
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		nav_left.emit()
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		nav_right.emit()
	elif event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		nav_up.emit()
	elif event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		nav_down.emit()
	elif event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		grab_focus()
		pick_requested.emit(item_index)
		get_viewport().set_input_as_handled()
