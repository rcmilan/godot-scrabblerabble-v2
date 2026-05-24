# res://scripts/desktop_icon.gd
extends Control

signal activated(icon_id: StringName)

const DOUBLE_CLICK_MS:   int   = 400
const DRAG_THRESHOLD_PX: float = 6.0

const BODY_SIZE:    Vector2 = Vector2(48, 48)
const BODY_TOP_PAD: float   = 4.0
const CAPTION_H:    float   = 18.0
const TOTAL_SIZE:   Vector2 = Vector2(80, 74)

# Tile / modifier palette (mirrors tile.gd so the shop visual reads as the
# same kind of object the player will get on their rack).
const C_OUTER_LIGHT := Color("#FFFFFF")
const C_INNER_LIGHT := Color("#DFDFDF")
const C_INNER_DARK  := Color("#808080")
const C_OUTER_DARK  := Color("#0A0A0A")
const C_MOD_GRADIENT_LEFT  := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)

const C_CHROME       := Color(0.7529, 0.7529, 0.7529, 1.0)
const C_TITLEBAR     := Color(0.0,    0.0,    0.5019, 1.0)
const C_FOLDER_BODY  := Color(1.0,    0.8392, 0.2,    1.0)
const C_FOLDER_EDGE  := Color(0.2,    0.1,    0.0,    1.0)
const C_FOLDER_SHADE := Color(0.7,    0.5568, 0.0,    1.0)
const C_LABEL        := Color(1.0, 1.0, 1.0, 1.0)
const C_LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const C_FOCUS_BORDER := Color(1.0, 1.0, 0.4, 1.0)

@export var icon_id:              StringName = &""
@export var requires_double_click: bool      = false

var focused_highlight: bool = false

var _last_click_ms: int     = -1
var _press_pos:     Vector2 = Vector2.ZERO
var _pressed:       bool    = false
var _dragging:      bool    = false

@onready var _caption: Label = $Caption

func _ready() -> void:
	mouse_filter        = MOUSE_FILTER_STOP
	custom_minimum_size = TOTAL_SIZE
	focus_mode          = FOCUS_ALL
	_caption.text = _caption_text()
	queue_redraw()

func _caption_text() -> String:
	match icon_id:
		&"mod_2x":         return "mod-2x.exe"
		&"user":           return "user"
		&"scrabblerabble": return "scrabblerabble.exe"
		_:                 return String(icon_id)

# ---------- Drawing ----------

func _draw() -> void:
	var body_rect := _body_rect()
	match icon_id:
		&"mod_2x":         _draw_mod2x_body(body_rect)
		&"user":           _draw_folder_body(body_rect)
		&"scrabblerabble": _draw_window_body(body_rect)
	if focused_highlight:
		# Outline the full icon (body + caption) so the cursor reads as
		# selecting the whole desktop icon, Win95-style.
		draw_rect(Rect2(Vector2.ZERO, size), C_FOCUS_BORDER, false, 1.0)

func _body_rect() -> Rect2:
	var pos := Vector2((TOTAL_SIZE.x - BODY_SIZE.x) * 0.5, BODY_TOP_PAD)
	return Rect2(pos, BODY_SIZE)

func _draw_mod2x_body(rect: Rect2) -> void:
	# Win98 gradient body + Win95 bevel + "2x" overlay so it reads as
	# "this is a 2x modifier" without implying a specific letter is granted.
	_draw_horizontal_gradient(Rect2(rect.position + Vector2(1, 1),
		rect.size - Vector2(2, 2)), C_MOD_GRADIENT_LEFT, C_MOD_GRADIENT_RIGHT)
	_draw_win95_bevel(rect)
	var font := get_theme_default_font()
	if font:
		var label := "2x"
		var size_px := 22
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, size_px)
		var center := rect.position + rect.size * 0.5
		var baseline := center + Vector2(-text_size.x * 0.5,
			font.get_ascent(size_px) - text_size.y * 0.5)
		draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, C_LABEL)

func _draw_folder_body(rect: Rect2) -> void:
	# Classic manila folder: a tab on top, a body below, dark edges.
	var tab_w := rect.size.x * 0.45
	var tab_h := rect.size.y * 0.22
	var tab := Rect2(rect.position + Vector2(2, 4), Vector2(tab_w, tab_h))
	var body := Rect2(rect.position + Vector2(0, tab_h + 2),
		Vector2(rect.size.x, rect.size.y - tab_h - 4))
	draw_rect(tab, C_FOLDER_BODY, true)
	draw_rect(tab, C_FOLDER_EDGE, false, 1.0)
	draw_rect(body, C_FOLDER_BODY, true)
	# bottom-right shading line for a tiny bit of depth
	draw_line(body.position + Vector2(0, body.size.y - 1),
		body.position + body.size - Vector2(1, 1), C_FOLDER_SHADE)
	draw_line(body.position + body.size - Vector2(1, 1),
		body.position + Vector2(body.size.x - 1, 0), C_FOLDER_SHADE)
	draw_rect(body, C_FOLDER_EDGE, false, 1.0)

func _draw_window_body(rect: Rect2) -> void:
	# Mini Win95 window: chrome rectangle with a navy titlebar, raised bevel.
	draw_rect(rect, C_CHROME, true)
	var titlebar := Rect2(rect.position + Vector2(2, 2),
		Vector2(rect.size.x - 4, 8))
	draw_rect(titlebar, C_TITLEBAR, true)
	# Two faint horizontal lines suggesting a content area.
	var line_y := titlebar.position.y + titlebar.size.y + 4
	for i in 3:
		draw_line(Vector2(rect.position.x + 4, line_y + i * 4),
			Vector2(rect.position.x + rect.size.x - 5, line_y + i * 4),
			C_INNER_DARK)
	_draw_win95_bevel(rect)

func _draw_win95_bevel(rect: Rect2) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	draw_line(Vector2(x,         y),         Vector2(x + w - 1, y),         C_OUTER_LIGHT)
	draw_line(Vector2(x,         y),         Vector2(x,         y + h - 1), C_OUTER_LIGHT)
	draw_line(Vector2(x + 1,     y + 1),     Vector2(x + w - 2, y + 1),     C_INNER_LIGHT)
	draw_line(Vector2(x + 1,     y + 1),     Vector2(x + 1,     y + h - 2), C_INNER_LIGHT)
	draw_line(Vector2(x + w - 2, y + 1),     Vector2(x + w - 2, y + h - 2), C_INNER_DARK)
	draw_line(Vector2(x + 1,     y + h - 2), Vector2(x + w - 2, y + h - 2), C_INNER_DARK)
	draw_line(Vector2(x + w - 1, y),         Vector2(x + w - 1, y + h - 1), C_OUTER_DARK)
	draw_line(Vector2(x,         y + h - 1), Vector2(x + w - 1, y + h - 1), C_OUTER_DARK)

func _draw_horizontal_gradient(rect: Rect2, c0: Color, c1: Color) -> void:
	var steps := int(rect.size.x)
	for i in steps:
		var t := float(i) / float(max(1, steps - 1))
		var c := c0.lerp(c1, t)
		draw_rect(Rect2(rect.position.x + i, rect.position.y, 1.0, rect.size.y), c)

func set_focused_highlight(value: bool) -> void:
	if focused_highlight == value:
		return
	focused_highlight = value
	queue_redraw()

# ---------- Input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragging = false
			_press_pos = event.position
		else:
			if _pressed and not _dragging:
				_handle_click()
			_pressed = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressed and not _dragging:
		if event.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
			_start_drag()

func _handle_click() -> void:
	if not requires_double_click:
		activated.emit(icon_id)
		return
	var now := Time.get_ticks_msec()
	if _last_click_ms >= 0 and (now - _last_click_ms) <= DOUBLE_CLICK_MS:
		_last_click_ms = -1
		activated.emit(icon_id)
	else:
		_last_click_ms = now

func _start_drag() -> void:
	if icon_id != &"mod_2x":
		return
	var preview_root := Control.new()
	var ghost: Control = duplicate(DUPLICATE_USE_INSTANTIATION) as Control
	# The duplicate's caption stays for honesty about what's being dragged,
	# but knock down its caption visibility a notch via modulate at the root.
	ghost.modulate = Color(1, 1, 1, 0.8)
	ghost.position = -TOTAL_SIZE * 0.5
	preview_root.add_child(ghost)
	force_drag({"icon_id": "mod_2x"}, preview_root)

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if icon_id != &"user":
		return false
	return typeof(data) == TYPE_DICTIONARY and data.get("icon_id") == "mod_2x"

func _drop_data(_pos: Vector2, _data: Variant) -> void:
	if icon_id != &"user":
		return
	var parent := get_parent()
	if parent and parent.has_method("on_mod2x_picked"):
		parent.on_mod2x_picked()

func flash_feedback() -> void:
	var original_modulate := modulate
	var original_filter   := mouse_filter
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	modulate = original_modulate
	mouse_filter = original_filter

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_pressed = false
		_dragging = false
