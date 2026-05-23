# res://scripts/desktop.gd
extends CanvasLayer

signal resume_requested

var _focused_icon_index: int = 0
var _icons: Array = []

func _ready() -> void:
	# Set background to fill the viewport
	var background := $Background
	if background:
		background.anchor_left = 0.0
		background.anchor_top = 0.0
		background.anchor_right = 1.0
		background.anchor_bottom = 1.0
		background.offset_left = 0
		background.offset_top = 0
		background.offset_right = 0
		background.offset_bottom = 0

	# Set up icons array for keyboard navigation
	_icons = [$Mod2xIcon, $UserIcon, $ScrabblerabbleIcon]

	# Set up icon signal connections
	$Mod2xIcon.activated.connect(_on_mod2x_activated)
	$ScrabblerabbleIcon.activated.connect(_on_scrabblerabble_activated)

	# Set initial focus
	_set_icon_focused(0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_move_focus_forward()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_DOWN:
				_move_focus_forward()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_UP:
				_move_focus_backward()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_SPACE:
				_activate_focused_icon()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_resume_game()
				get_viewport().set_input_as_handled()

func _move_focus_forward() -> void:
	_focused_icon_index = (_focused_icon_index + 1) % _icons.size()
	_set_icon_focused(_focused_icon_index)

func _move_focus_backward() -> void:
	_focused_icon_index = (_focused_icon_index - 1 + _icons.size()) % _icons.size()
	_set_icon_focused(_focused_icon_index)

func _set_icon_focused(index: int) -> void:
	_focused_icon_index = index
	# Remove focus highlight from all icons
	for icon in _icons:
		if icon.is_visible_in_tree():
			icon.modulate = Color.WHITE
	# Add focus highlight to current icon
	var focused_icon = _icons[index]
	if focused_icon.is_visible_in_tree():
		focused_icon.modulate = Color.YELLOW
		focused_icon.grab_focus()

func _activate_focused_icon() -> void:
	var icon = _icons[_focused_icon_index]
	if not icon.is_visible_in_tree():
		return
	if icon.icon_id == &"user":
		# User folder is drop-only, no activation via keyboard
		return
	# Simulate a click on the focused icon
	icon.activated.emit(icon.icon_id)

func _resume_game() -> void:
	resume_requested.emit()

func _on_mod2x_activated(icon_id: StringName) -> void:
	if icon_id == &"mod_2x":
		RunState.add_to_build(GameData.MOD_2X)
		# Flash feedback and then hide
		await $Mod2xIcon._flash_feedback()
		$Mod2xIcon.visible = false
		# Move focus to next available icon
		_move_focus_forward()

func _on_mod2x_dropped() -> void:
	# Called when mod-2x is dropped onto the user folder
	RunState.add_to_build(GameData.MOD_2X)
	# Flash feedback and then hide
	await $Mod2xIcon._flash_feedback()
	$Mod2xIcon.visible = false
	# Move focus to next available icon
	_move_focus_forward()

func _on_scrabblerabble_activated(icon_id: StringName) -> void:
	if icon_id == &"scrabblerabble":
		resume_requested.emit()
