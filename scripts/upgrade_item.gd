class_name UpgradeItem
extends Control

signal selected(index: int)
signal confirmed(index: int)
signal nav_left
signal nav_right
signal nav_up
signal nav_down

const BODY_SIZE := Vector2(56.0, 56.0)

const C_OUTER_LIGHT          := Color("#FFFFFF")
const C_INNER_LIGHT          := Color("#DFDFDF")
const C_INNER_DARK           := Color("#808080")
const C_OUTER_DARK           := Color("#0A0A0A")
const C_MOD_GRADIENT_LEFT    := Color(0.0,        0.0,         0.5019, 1.0)
const C_MOD_GRADIENT_RIGHT   := Color(16.0/255.0, 132.0/255.0, 208.0/255.0, 1.0)
const C_MOD3X_GRADIENT_LEFT  := Color(0.0,        0.376, 0.0,   1.0)
const C_MOD3X_GRADIENT_RIGHT := Color(0.188,       0.753, 0.188, 1.0)
const C_LABEL_LETTER         := Color(1.0, 1.0, 1.0, 1.0)
const C_LABEL_POINT          := Color(1.0, 1.0, 1.0, 1.0)
const C_SELECTION_BORDER     := Color(1.0, 1.0, 0.0, 1.0)
const C_BAG_COUNT            := Color(0.251, 0.251, 0.251, 1.0)

var item_index: int    = 0
var letter: String     = "A"
var modifier: String   = ""
var is_selected: bool  = false

func _ready() -> void:
	focus_mode          = FOCUS_ALL
	custom_minimum_size = Vector2(88.0, 96.0)
	mouse_filter        = MOUSE_FILTER_STOP
	focus_entered.connect(emit_selected)
	focus_exited.connect(queue_redraw)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for child in get_children():
		if child is Control:
			(child as Control).focus_mode   = FOCUS_NONE
			(child as Control).mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	var body_x   := (size.x - BODY_SIZE.x) * 0.5
	var tile_rect := Rect2(Vector2(body_x, 0.0), BODY_SIZE)

	# Draw tile body with modifier gradient
	if modifier == GameData.MOD_3X:
		_draw_mod3x_body(tile_rect)
	else:
		_draw_mod2x_body(tile_rect)

	# Draw letter and point value on the tile
	var font := get_theme_default_font()
	if font:
		# Letter: 24px, centered
		var font_size_letter := 24
		var letter_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_letter)
		var letter_pos := Vector2(
			tile_rect.get_center().x - letter_size.x * 0.5,
			tile_rect.get_center().y + font.get_ascent(font_size_letter) * 0.5 - letter_size.y * 0.5 - 2.0
		)
		draw_string(font, letter_pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_letter, C_LABEL_LETTER)

		# Point value: 9px, bottom-right of tile
		var point_value := GameData.score_for_letter(letter)
		var font_size_pts := 9
		var pts_str := str(point_value)
		var pts_size := font.get_string_size(pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_pts)
		var pts_pos := Vector2(
			tile_rect.position.x + tile_rect.size.x - pts_size.x - 2.0,
			tile_rect.position.y + tile_rect.size.y - 2.0
		)
		draw_string(font, pts_pos, pts_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_pts, C_LABEL_POINT)

	# Draw selection border around tile
	if is_selected:
		draw_rect(tile_rect.grow(2.0), C_SELECTION_BORDER, false, 2.0)

	# Draw "N in bag" below the tile
	if font:
		var bag_count: int = GameData.LETTER_DISTRIBUTION.get(letter, 0)
		var bag_text := "%d in bag" % bag_count
		var font_size_bag := 12
		var bag_size := font.get_string_size(bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_bag)
		var bag_pos := Vector2(
			body_x + (BODY_SIZE.x - bag_size.x) * 0.5,
			tile_rect.position.y + BODY_SIZE.y + 16.0
		)
		draw_string(font, bag_pos, bag_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size_bag, C_BAG_COUNT)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		emit_confirmed()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			grab_focus()
			emit_selected()
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed and mouse_event.double_click:
			emit_confirmed()
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

func emit_selected() -> void:
	selected.emit(item_index)

func emit_confirmed() -> void:
	confirmed.emit(item_index)

func _draw_mod3x_body(rect: Rect2) -> void:
	_draw_horizontal_gradient(
		Rect2(rect.position + Vector2(1, 1), rect.size - Vector2(2, 2)),
		C_MOD3X_GRADIENT_LEFT, C_MOD3X_GRADIENT_RIGHT)
	_draw_win95_bevel(rect)

func _draw_mod2x_body(rect: Rect2) -> void:
	_draw_horizontal_gradient(
		Rect2(rect.position + Vector2(1, 1), rect.size - Vector2(2, 2)),
		C_MOD_GRADIENT_LEFT, C_MOD_GRADIENT_RIGHT)
	_draw_win95_bevel(rect)

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
