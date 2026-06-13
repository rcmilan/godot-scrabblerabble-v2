class_name UpgradeDialog
extends Control

signal upgrade_picked(offer: Dictionary)
signal skipped

@onready var _grid:       GridContainer = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/Grid
@onready var _caption:    Label         = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/Caption
@onready var _banner:     Control       = $CenterContainer/Window/RootVBox/BodyArea/Banner
@onready var _back_btn:   Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/BackButton
@onready var _next_btn:   Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/NextButton
@onready var _cancel_btn: Button        = $CenterContainer/Window/RootVBox/BodyArea/BodyMargin/ContentVBox/ButtonRow/CancelButton
@onready var _close_btn:  Button        = $CenterContainer/Window/RootVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _offers:     Array[Dictionary] = []
var _item_nodes: Array[UpgradeItem] = []
var _selected_index: int = 0

func _ready() -> void:
	_close_btn.pressed.connect(_on_skip)
	_cancel_btn.pressed.connect(_on_skip)
	_next_btn.pressed.connect(_on_next_pressed)
	_next_btn.gui_input.connect(_on_next_btn_gui_input)
	_banner.custom_minimum_size = Vector2(96, 0)
	_banner.draw.connect(_on_banner_draw)

func populate(offers: Array[Dictionary]) -> void:
	_offers = offers.duplicate()

	# Clear previous items
	for child in _grid.get_children():
		child.queue_free()
	_item_nodes.clear()

	var count: int = _offers.size()
	_grid.columns = 2

	# Build one UpgradeItem per offer
	for i in count:
		var offer: Dictionary = _offers[i]
		var item := UpgradeItem.new()
		item.item_index    = i
		item.letter        = offer.get("letter", "A")
		item.modifier      = offer.get("modifier", GameData.MOD_2X)
		item.is_selected   = (i == 0)
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item.selected.connect(_on_item_selected)
		item.confirmed.connect(_on_item_confirmed)
		_grid.add_child(item)
		_item_nodes.append(item)

	# Wire navigation (2-column grid)
	for i in _item_nodes.size():
		var captured_i := i
		_item_nodes[i].nav_left.connect(func(): _nav_horizontal(captured_i, -1))
		_item_nodes[i].nav_right.connect(func(): _nav_horizontal(captured_i, 1))
		_item_nodes[i].nav_up.connect(func(): _nav_vertical(captured_i, -1))
		_item_nodes[i].nav_down.connect(func(): _nav_vertical(captured_i, 1))

	_selected_index = 0
	_update_caption()
	_banner.queue_redraw()
	print("[UpgradeWizard] shown — %d offers" % count)

func focus_first() -> void:
	if not _item_nodes.is_empty() and is_instance_valid(_item_nodes[0]):
		_item_nodes[0].grab_focus()
	else:
		_next_btn.grab_focus()

func _on_item_selected(index: int) -> void:
	_selected_index = index
	for i in _item_nodes.size():
		_item_nodes[i].is_selected = (i == index)
		_item_nodes[i].queue_redraw()
	_update_caption()
	print("[UpgradeWizard] selected — %s ×%s" % [
		_offers[index].get("letter", "?"),
		_offers[index].get("modifier", "?")
	])

func _on_item_confirmed(index: int) -> void:
	if index >= 0 and index < _offers.size():
		_confirm_selection(index)

func _on_next_pressed() -> void:
	_confirm_selection(_selected_index)

func _confirm_selection(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	var offer: Dictionary = _offers[index]
	print("[UpgradeWizard] confirmed — %s ×%s" % [
		offer.get("letter", "?"),
		offer.get("modifier", "?")
	])
	upgrade_picked.emit(offer)

const GRID_COLUMNS := 2

func _nav_horizontal(from_index: int, delta: int) -> void:
	var new_col := (from_index % GRID_COLUMNS) + delta
	if new_col < 0 or new_col >= GRID_COLUMNS:
		return
	var target := from_index + delta
	if target >= 0 and target < _item_nodes.size():
		_item_nodes[target].grab_focus()

func _nav_vertical(from_index: int, delta_rows: int) -> void:
	var target := from_index + delta_rows * GRID_COLUMNS
	if target >= 0 and target < _item_nodes.size():
		_item_nodes[target].grab_focus()
	elif delta_rows > 0:
		_next_btn.grab_focus()

func _on_skip() -> void:
	print("[UpgradeWizard] skipped")
	skipped.emit()

func _update_caption() -> void:
	if _selected_index < 0 or _selected_index >= _offers.size():
		_caption.text = ""
		return
	var offer: Dictionary = _offers[_selected_index]
	var letter: String = offer.get("letter", "?")
	var modifier: String = offer.get("modifier", "")
	var mod_word := "double" if modifier == GameData.MOD_2X else "triple"
	_caption.text = "Every %s tile scores %s points for the rest of the run." % [letter, mod_word]

func _on_banner_draw() -> void:
	var banner_rect := _banner.get_rect()
	var steps := int(banner_rect.size.y)
	var navy := Color(0, 0, 0.5019, 1.0)
	var deep := Color(0, 0, 0.20, 1.0)
	for i in steps:
		var t := float(i) / float(max(1, steps - 1))
		_banner.draw_rect(Rect2(0, i, banner_rect.size.x, 1), navy.lerp(deep, t))

	var font := _banner.get_theme_default_font()
	if font:
		var text := "ScrabbleRabble 95"
		var font_size := 16
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var centre := banner_rect.size * 0.5
		_banner.draw_set_transform(centre, -PI / 2.0, Vector2.ONE)
		_banner.draw_string(font, Vector2(-text_w * 0.5, 0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 1))
		_banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _on_next_btn_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		if _selected_index >= 0 and _selected_index < _item_nodes.size():
			_item_nodes[_selected_index].grab_focus()
		get_viewport().set_input_as_handled()
