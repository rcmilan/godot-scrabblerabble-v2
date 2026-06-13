class_name UpgradeDialog
extends Panel

signal upgrade_picked(offer: Dictionary)
signal skipped

@onready var _grid:          GridContainer = $InnerVBox/BodyArea/ContentVBox/Grid
@onready var _caption:       Label         = $InnerVBox/BodyArea/ContentVBox/Caption
@onready var _banner:        Control       = $InnerVBox/BodyArea/Banner
@onready var _back_btn:      Button        = $InnerVBox/BodyArea/ContentVBox/ButtonRow/BackButton
@onready var _next_btn:      Button        = $InnerVBox/BodyArea/ContentVBox/ButtonRow/NextButton
@onready var _cancel_btn:    Button        = $InnerVBox/BodyArea/ContentVBox/ButtonRow/CancelButton
@onready var _close_btn:     Button        = $InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _offers:     Array[Dictionary] = []
var _item_nodes: Array[UpgradeItem] = []
var _selected_index: int = 0

func _ready() -> void:
	_close_btn.pressed.connect(_on_skip)
	_cancel_btn.pressed.connect(_on_skip)
	_next_btn.pressed.connect(_on_next_pressed)
	_banner.custom_minimum_size = Vector2(96, 0)
	_banner.draw.connect(_on_banner_draw)

func populate(offers: Array[Dictionary]) -> void:
	_offers = offers.duplicate()

	# Clear previous items
	for child in _grid.get_children():
		child.queue_free()
	_item_nodes.clear()

	var count: int = _offers.size()
	_grid.columns = max(1, int(ceil(sqrt(float(count)))))

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

	# Wire navigation
	for i in _item_nodes.size():
		var item := _item_nodes[i]
		var captured_i := i
		item.nav_left.connect(func(): _on_item_nav_left(captured_i))
		item.nav_right.connect(func(): _on_item_nav_right(captured_i))
		item.nav_up.connect(func(): _next_btn.grab_focus())
		item.nav_down.connect(func(): _next_btn.grab_focus())

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

func _on_item_nav_left(i: int) -> void:
	if i > 0:
		_item_nodes[i - 1].grab_focus()

func _on_item_nav_right(i: int) -> void:
	if i < _item_nodes.size() - 1:
		_item_nodes[i + 1].grab_focus()

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
	var black := Color.BLACK
	for i in steps:
		var t := float(i) / float(max(1, steps - 1))
		var color := navy.lerp(black, t)
		_banner.draw_rect(Rect2(0, i, banner_rect.size.x, 1), color)
