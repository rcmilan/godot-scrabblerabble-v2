class_name UpgradeItem
extends Control

signal pick_requested(index: int)
signal board_focus_requested

const BODY_SIZE := Vector2(72.0, 72.0)

const C_OUTER_LIGHT          := Color("#FFFFFF")
const C_INNER_LIGHT          := Color("#DFDFDF")
const C_INNER_DARK           := Color("#808080")
const C_OUTER_DARK           := Color("#0A0A0A")
const C_MOD_GRADIENT_LEFT    := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT   := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)
const C_LABEL                := Color(1.0, 1.0, 1.0, 1.0)
const C_FOCUS_BORDER         := Color(1.0, 1.0, 0.4, 1.0)

var item_index: int    = 0
var upgrade_id: String = ""

func _ready() -> void:
	focus_mode          = FOCUS_ALL
	custom_minimum_size = Vector2(0.0, BODY_SIZE.y + 8.0)
	mouse_filter        = MOUSE_FILTER_STOP
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var body_x   := (size.x - BODY_SIZE.x) * 0.5
	var body_rect := Rect2(Vector2(body_x, 4.0), BODY_SIZE)
	_draw_mod2x_body(body_rect)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), C_FOCUS_BORDER, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		pick_requested.emit(item_index)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_cancel"):
		board_focus_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var prev := _sibling(-1)
		if prev:
			prev.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var next := _sibling(1)
		if next:
			next.grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		grab_focus()
		pick_requested.emit(item_index)
		get_viewport().set_input_as_handled()

func _sibling(delta: int) -> UpgradeItem:
	var parent := get_parent()
	if not parent:
		return null
	var items: Array = parent.get_children().filter(func(c): return c is UpgradeItem)
	var idx := items.find(self)
	var target := idx + delta
	if target >= 0 and target < items.size():
		return items[target] as UpgradeItem
	return null

# --- drawing helpers (mirrors desktop_icon.gd) ---

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
