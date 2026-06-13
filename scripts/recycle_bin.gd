class_name RecycleBin
extends Control

const BIN_SIZE := Vector2(52.0, 60.0)
const C_LIGHT := Color("#FFFFFF")
const C_DARK  := Color("#0A0A0A")
const C_BODY  := Color("#C0C0C0")
const C_GRAY  := Color("#808080")
const C_NAVY  := Color(0, 0, 0.5019, 1.0)

func _ready() -> void:
	custom_minimum_size = BIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	RunState.discards_left_changed.connect(func(_n: int) -> void: queue_redraw())
	queue_redraw()

func _enabled() -> bool:
	if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading:
		return false
	return RunState.discards_left > 0

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _enabled() and data is Tile and (data as Tile).location == "rack"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("discard_rack_tile"):
		main.discard_rack_tile(data as Tile)

func _draw() -> void:
	var enabled := RunState.discards_left > 0
	var body := C_BODY if enabled else C_GRAY
	# Simple Win95 bin: lid + trapezoid body with ribs.
	var w := 28.0
	var x := (size.x - w) * 0.5
	# lid
	draw_rect(Rect2(x - 3.0, 6.0, w + 6.0, 5.0), body)
	draw_rect(Rect2(x - 3.0, 6.0, w + 6.0, 5.0), C_DARK, false, 1.0)
	# body
	var body_rect := Rect2(x, 12.0, w, 30.0)
	draw_rect(body_rect, body)
	draw_rect(body_rect, C_DARK, false, 1.0)
	for i in 3:
		var rx := x + 6.0 + i * 8.0
		draw_line(Vector2(rx, 15.0), Vector2(rx, 39.0), C_DARK)
	# count
	var font := get_theme_default_font()
	if font:
		var t := str(RunState.discards_left)
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, Vector2((size.x - ts.x) * 0.5, 56.0), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_NAVY if enabled else C_GRAY)
