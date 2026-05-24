# res://scripts/desktop.gd
extends CanvasLayer

signal resume_requested

var _icons: Array = []
var _focused_icon_index: int = 0

func _ready() -> void:
	_icons = [$Mod2xIcon, $UserIcon, $ScrabblerabbleIcon]
	$Mod2xIcon.activated.connect(_on_icon_activated)
	$ScrabblerabbleIcon.activated.connect(_on_icon_activated)
	_set_icon_focused(0)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_TAB, KEY_RIGHT, KEY_DOWN:
			_move_focus(1)
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_UP:
			_move_focus(-1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_SPACE:
			_activate_focused_icon()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			resume_requested.emit()
			get_viewport().set_input_as_handled()

func _move_focus(direction: int) -> void:
	# Walk in `direction` until a visible icon is found; give up after one
	# full loop so a fully-empty desktop doesn't spin.
	var n := _icons.size()
	for step in range(1, n + 1):
		var idx := (_focused_icon_index + direction * step + n * n) % n
		if _icons[idx].is_visible_in_tree():
			_set_icon_focused(idx)
			return

func _set_icon_focused(index: int) -> void:
	_focused_icon_index = index
	for i in _icons.size():
		_icons[i].set_focused_highlight(i == index and _icons[i].is_visible_in_tree())
	var focused: Control = _icons[index]
	if focused.is_visible_in_tree():
		focused.grab_focus()

func _activate_focused_icon() -> void:
	var icon = _icons[_focused_icon_index]
	if not icon.is_visible_in_tree():
		return
	if icon.icon_id == &"user":
		return  # drop-only
	icon.activated.emit(icon.icon_id)

func _on_icon_activated(icon_id: StringName) -> void:
	match icon_id:
		&"mod_2x":         on_mod2x_picked()
		&"scrabblerabble": resume_requested.emit()

# Called for both double-click on mod-2x and drop on user folder.
func on_mod2x_picked() -> void:
	if not $Mod2xIcon.visible:
		return
	RunState.add_to_build(GameData.MOD_2X)
	await $Mod2xIcon.flash_feedback()
	$Mod2xIcon.visible = false
	_move_focus(1)
