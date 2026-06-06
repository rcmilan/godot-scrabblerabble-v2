class_name UpgradeDialog
extends Panel

signal upgrade_picked(upgrade_id: String)
signal skipped

@onready var _grid:     GridContainer = $InnerVBox/BodyArea/Grid
@onready var _skip_btn: Button        = $InnerVBox/BodyArea/ButtonRow/SkipButton
@onready var _close_btn: Button       = $InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _upgrades:   Array[Dictionary] = []
var _item_nodes: Array[UpgradeItem] = []

func _ready() -> void:
	_skip_btn.pressed.connect(_on_skip)
	_close_btn.pressed.connect(_on_skip)

func populate(upgrades: Array[Dictionary]) -> void:
	_upgrades = upgrades.duplicate()

	# Clear any previous items.
	for child in _grid.get_children():
		child.queue_free()
	_item_nodes.clear()

	# Compute column count for a roughly square layout.
	var count: int = _upgrades.size()
	_grid.columns = max(1, int(ceil(sqrt(float(count)))))

	# Build one UpgradeItem per upgrade.
	for i in count:
		var data: Dictionary = _upgrades[i]
		var item := UpgradeItem.new()
		item.item_index    = i
		item.upgrade_id    = data.get("id", "")
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item.pick_requested.connect(_on_item_picked)
		_grid.add_child(item)
		_item_nodes.append(item)

	print("[UpgradeDialog] populated with %d upgrade(s)" % count)

func focus_first() -> void:
	if not _item_nodes.is_empty() and is_instance_valid(_item_nodes[0]):
		_item_nodes[0].grab_focus()
	else:
		_skip_btn.grab_focus()

# --- internal ---

func _on_item_picked(index: int) -> void:
	if index < 0 or index >= _upgrades.size():
		return
	var uid: String = _upgrades[index].get("id", "")
	print("[UpgradeDialog] picked id=%s" % uid)
	upgrade_picked.emit(uid)

func _on_skip() -> void:
	print("[UpgradeDialog] skipped")
	skipped.emit()
