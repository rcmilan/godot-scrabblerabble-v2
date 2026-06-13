class_name UpgradeItem
extends Control

signal pick_requested(index: int)
signal nav_left
signal nav_right
signal nav_up
signal nav_down

const BODY_SIZE := Vector2(72.0, 72.0)

const C_OUTER_LIGHT          := Color("#FFFFFF")
const C_INNER_LIGHT          := Color("#DFDFDF")
const C_INNER_DARK           := Color("#808080")
const C_OUTER_DARK           := Color("#0A0A0A")
const C_MOD_GRADIENT_LEFT    := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT   := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)
const C_MOD3X_GRADIENT_LEFT  := Color(0.0,        0.376, 0.0,   1.0)
const C_MOD3X_GRADIENT_RIGHT := Color(0.188,       0.753, 0.188, 1.0)
const C_LABEL                := Color(1.0, 1.0, 1.0, 1.0)
const C_FOCUS_BORDER         := Color(1.0, 1.0, 0.0, 1.0)

var item_index: int    = 0
var upgrade_id: String = ""

func _ready() -> void:
	focus_mode          = FOCUS_ALL
	custom_minimum_size = Vector2(BODY_SIZE.x, BODY_SIZE.y + 8.0)
	mouse_filter        = MOUSE_FILTER_STOP
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	# Suppress Godot's default focus StyleBox so it doesn't draw a caret.
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Ensure no child node can steal focus or render its own caret.
	for child in get_children():
		if child is Control:
			(child as Control).focus_mode   = FOCUS_NONE
			(child as Control).mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	var body_x   := (size.x - BODY_SIZE.x) * 0.5
	var body_rect := Rect2(Vector2(body_x, 4.0), BODY_SIZE)
	if upgrade_id == GameData.MOD_3X:
		_draw_mod3x_body(body_rect)
	else:
		_draw_mod2x_body(body_rect)
	if has_focus():
		draw_rect(body_rect.grow(2.0), C_FOCUS_BORDER, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		pick_requested.emit(item_index)
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
	elif event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		grab_focus()
		pick_requested.emit(item_index)
		get_viewport().set_input_as_handled()

# --- drawing helpers (mirrors desktop_icon.gd) ---

func _draw_mod3x_body(rect: Rect2) -> void:
	_draw_horizontal_gradient(
		Rect2(rect.position + Vector2(1, 1), rect.size - Vector2(2, 2)),
		C_MOD3X_GRADIENT_LEFT, C_MOD3X_GRADIENT_RIGHT)
	_draw_win95_bevel(rect)
	var font := get_theme_default_font()
	if font:
		var size_px  := 28
		var text      = "3x"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size_px)
		var center    := rect.position + rect.size * 0.5
		var baseline  := center + Vector2(-text_size.x * 0.5,
				font.get_ascent(size_px) - text_size.y * 0.5)
		draw_string(font, baseline, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, C_LABEL)

func _draw_mod2x_body(rect: Rect2) -> void:
	_draw_horizontal_gradient(
		Rect2(rect.position + Vector2(1, 1), rect.size - Vector2(2, 2)),
		C_MOD_GRADIENT_LEFT, C_MOD_GRADIENT_RIGHT)
	_draw_win95_bevel(rect)
	var font := get_theme_default_font()
	if font:
		var size_px  := 28
		var text      = "2x"
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size_px)
		var center    := rect.position + rect.size * 0.5
		var baseline  := center + Vector2(-text_size.x * 0.5,
				font.get_ascent(size_px) - text_size.y * 0.5)
		draw_string(font, baseline, text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, C_LABEL)

func _draw_win95_bevel(rect: Rect2) -> void:
	var x := rect.position.x;  var y := rect.position.y
	var w := rect.size.x;      var h := rect.size.y
	draw_line(Vector2(x,     y),     Vector2(x+w-1, y),     C_OUTER_LIGHT)
	draw_line(Vector2(x,     y),     Vector2(x,     y+h-1), C_OUTER_LIGHT)
	draw_line(Vector2(x+1,   y+1),   Vector2(x+w-2, y+1),   C_INNER_LIGHT)
	draw_line(Vector2(x+1,   y+1),   Vector2(x+1,   y+h-2), C_INNER_LIGHT)
	draw_line(Vector2(x+w-2, y+1),   Vector2(x+w-2, y+h-2), C_INNER_DARK)
	draw_line(Vector2(x+1,   y+h-2), Vector2(x+w-2, y+h-2), C_INNER_DARK)
	draw_line(Vector2(x+w-1, y),     Vector2(x+w-1, y+h-1), C_OUTER_DARK)
	draw_line(Vector2(x,     y+h-1), Vector2(x+w-1, y+h-1), C_OUTER_DARK)

func _draw_horizontal_gradient(rect: Rect2, c0: Color, c1: Color) -> void:
	var steps := int(rect.size.x)
	for i in steps:
		var t := float(i) / float(max(1, steps - 1))
		draw_rect(Rect2(rect.position.x + i, rect.position.y, 1.0, rect.size.y), c0.lerp(c1, t))
