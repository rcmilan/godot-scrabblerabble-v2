class_name LetterItem
extends Control

signal pick_requested(index: int)
signal nav_left
signal nav_right
signal nav_up
signal nav_down

const BODY_SIZE := Vector2(40.0, 52.0)
const C_FOCUS_BORDER := Color(1, 1, 0, 1)
const C_TILE_BG      := Color(0.96, 0.92, 0.78, 1.0)
const C_TILE_BORDER  := Color(0.3, 0.2, 0.1, 1.0)
const C_LETTER       := Color(0.05, 0.05, 0.05, 1.0)
const C_PTS          := Color(0.25, 0.2, 0.1, 1.0)

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
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return

	draw_rect(Rect2(Vector2.ZERO, sz), C_TILE_BORDER, true)
	draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), C_TILE_BG, true)

	var font := get_theme_default_font()
	if font:
		var font_size_letter := 22
		var letter_size := font.get_string_size(_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_letter)
		var letter_pos := Vector2((sz.x - letter_size.x) * 0.5, (sz.y + letter_size.y) * 0.5 - 8)
		draw_string(font, letter_pos, _letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_letter, C_LETTER)

		var font_size_pts := 10
		var pts_str := str(_points)
		var pts_size := font.get_string_size(pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_pts)
		var pts_pos := Vector2(sz.x - pts_size.x - 3, sz.y - 3)
		draw_string(font, pts_pos, pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_pts, C_PTS)

	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, sz), C_FOCUS_BORDER, false, 2.0)

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
