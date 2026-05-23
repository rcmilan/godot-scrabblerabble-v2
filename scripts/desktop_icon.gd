# res://scripts/desktop_icon.gd
extends Control

signal activated(icon_id: StringName)

const DOUBLE_CLICK_MS: int = 400
const DRAG_THRESHOLD_PX: float = 6.0
const TILE_SCENE: PackedScene = preload("res://scenes/tile.tscn")

@export var icon_id: StringName = &""
@export var requires_double_click: bool = false

var _last_click_ms: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _dragging: bool = false
var _icon_visual: Control = null
var _label: Label = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(80, 100)
	_setup_visual()

func _setup_visual() -> void:
	# For mod_2x, create a tile visual; for others, create a simple icon
	match icon_id:
		&"mod_2x":
			_setup_mod2x_visual()
		&"user":
			_setup_user_visual()
		&"scrabblerabble":
			_setup_scrabblerabble_visual()

func _setup_mod2x_visual() -> void:
	# Create a container for the icon and label
	var container = VBoxContainer.new()
	add_child(container)

	# Create a tile visual with a random letter and MOD_2X modifier
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(RunState.current_round)
	var letters := GameData.LETTER_DISTRIBUTION.keys()
	var random_letter: String = letters[rng.randi() % letters.size()]

	var tile := TILE_SCENE.instantiate() as Tile
	tile.letter = random_letter
	tile.set_modifier(GameData.MOD_2X)
	tile.custom_minimum_size = Vector2(48, 48)
	container.add_child(tile)
	_icon_visual = tile

	# Add label
	_label = Label.new()
	_label.text = "mod-2x.exe"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(_label)

func _setup_user_visual() -> void:
	# Create a container
	var container = VBoxContainer.new()
	add_child(container)

	# Create a simple folder-like icon
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(48, 48)
	panel.modulate = Color(0.7, 0.7, 0.7)
	container.add_child(panel)

	var label_icon := Label.new()
	label_icon.text = "📁"
	label_icon.add_theme_font_size_override("font_size", 24)
	panel.add_child(label_icon)
	_icon_visual = panel

	# Add label
	_label = Label.new()
	_label.text = "user"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(_label)

func _setup_scrabblerabble_visual() -> void:
	# Create a container
	var container = VBoxContainer.new()
	add_child(container)

	# Create a simple game icon
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(48, 48)
	panel.modulate = Color(0.4, 0.4, 0.8)
	container.add_child(panel)

	var label_icon := Label.new()
	label_icon.text = "🎮"
	label_icon.add_theme_font_size_override("font_size", 24)
	panel.add_child(label_icon)
	_icon_visual = panel

	# Add label
	_label = Label.new()
	_label.text = "scrabblerabble.exe"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(_label)

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
	# Only mod_2x can be dragged; user folder is drop-only
	if icon_id != &"mod_2x":
		return

	var preview := Control.new()
	var ghost := Panel.new()
	ghost.custom_minimum_size = Vector2(48, 48)
	ghost.modulate = Color(1, 1, 1, 0.7)
	preview.add_child(ghost)
	force_drag({"icon_id": "mod_2x"}, preview)

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	# Only user folder accepts drops
	if icon_id != &"user":
		return false
	return typeof(data) == TYPE_DICTIONARY and data.get("icon_id") == "mod_2x"

func _drop_data(_pos: Vector2, _data: Variant) -> void:
	# Only user folder processes drops
	if icon_id != &"user":
		return
	# Notify parent desktop that mod_2x was dropped
	var parent = get_parent()
	if parent and parent.has_method("_on_mod2x_dropped"):
		parent._on_mod2x_dropped()

func _flash_feedback() -> void:
	# Flash the icon briefly (white for 100ms, then back to normal)
	var original_modulate := modulate
	modulate = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	modulate = original_modulate

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_pressed = false
		_dragging = false
