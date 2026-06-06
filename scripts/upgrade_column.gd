class_name UpgradeColumn
extends Panel

signal upgrade_picked(upgrade_id: String)
signal upgrade_count_changed(count: int)
signal request_board_focus

@onready var _body_area: VBoxContainer = $InnerVBox/BodyArea

var _upgrades:   Array[Dictionary] = []
var _item_nodes: Array[UpgradeItem] = []

func _ready() -> void:
	visible = false

func add_upgrade(data: Dictionary) -> void:
	_upgrades.append(data)
	_build_item(data, _upgrades.size() - 1)
	visible = true
	print("[UpgradeColumn] add_upgrade id=%s — %d pending" % [data.get("id", "?"), _upgrades.size()])
	upgrade_count_changed.emit(_upgrades.size())

func is_empty() -> bool:
	return _upgrades.is_empty()

func has_focused_item() -> bool:
	for item in _item_nodes:
		if is_instance_valid(item) and item.has_focus():
			return true
	return false

func focus_first() -> void:
	if not _item_nodes.is_empty() and is_instance_valid(_item_nodes[0]):
		_item_nodes[0].grab_focus()

func pick_first() -> void:
	_pick(0)

# --- internal ---

func _build_item(data: Dictionary, index: int) -> void:
	var item := UpgradeItem.new()
	item.item_index = index
	item.upgrade_id = data.get("id", "")
	item.size_flags_horizontal = SIZE_FILL
	item.pick_requested.connect(_pick)
	item.board_focus_requested.connect(func(): request_board_focus.emit())
	_body_area.add_child(item)
	_item_nodes.append(item)

func _pick(index: int) -> void:
	if index < 0 or index >= _upgrades.size():
		return
	var data := _upgrades[index]
	var uid: String = data.get("id", "")
	print("[UpgradeColumn] picked id=%s" % uid)

	_upgrades.remove_at(index)
	_item_nodes[index].queue_free()
	_item_nodes.remove_at(index)

	# Re-index items that shifted down.
	for i in range(index, _item_nodes.size()):
		_item_nodes[i].item_index = i

	if _upgrades.is_empty():
		visible = false
		print("[UpgradeColumn] all upgrades picked — hiding column")

	upgrade_count_changed.emit(_upgrades.size())
	upgrade_picked.emit(uid)
