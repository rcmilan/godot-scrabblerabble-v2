class_name LetterPickerDialog
extends Panel

signal letter_picked(letter: String)
signal back_pressed

@onready var _grid     = $InnerVBox/BodyArea/LetterGrid
@onready var _back_btn = $InnerVBox/BodyArea/ButtonRow/BackButton
@onready var _close_btn = $InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _letters: Array[String] = []
var _item_nodes: Array = []

func _ready() -> void:
	_back_btn.focus_mode = FOCUS_ALL
	_back_btn.gui_input.connect(_on_back_btn_input)
	_close_btn.pressed.connect(func(): back_pressed.emit())

func populate(upgrade_id: String, letters: Array[String]) -> void:
	_letters = letters
	_item_nodes.clear()
	for child in _grid.get_children():
		child.queue_free()

	for i in range(letters.size()):
		var item := LetterItem.new()
		item.set_letter(letters[i])
		item.item_index = i
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_grid.add_child(item)
		_item_nodes.append(item)
		item.pick_requested.connect(_on_item_picked)
		item.nav_left.connect(_on_item_nav_left.bind(i))
		item.nav_right.connect(_on_item_nav_right.bind(i))
		item.nav_down.connect(_on_item_nav_down)
		item.nav_up.connect(_on_item_nav_down)

	print("[LetterPickerDialog] populated with %d letters for %s" % [letters.size(), upgrade_id])

func focus_first() -> void:
	if _item_nodes.size() > 0:
		_item_nodes[0].grab_focus()
	else:
		_back_btn.grab_focus()

func _on_item_picked(index: int) -> void:
	letter_picked.emit(_letters[index])

func _on_item_nav_left(index: int) -> void:
	if index > 0:
		_item_nodes[index - 1].grab_focus()

func _on_item_nav_right(index: int) -> void:
	if index < _item_nodes.size() - 1:
		_item_nodes[index + 1].grab_focus()

func _on_item_nav_down() -> void:
	_back_btn.grab_focus()

func _on_back_btn_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		if _item_nodes.size() > 0:
			_item_nodes[0].grab_focus()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
