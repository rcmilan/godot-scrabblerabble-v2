class_name UpgradeColumn
extends Panel

signal upgrade_picked(upgrade_id: String)
signal upgrade_count_changed(count: int)

const _LABEL_COLOR_NORMAL:   Color = Color(0.0,  0.0,  0.0,  1.0)
const _LABEL_COLOR_SELECTED: Color = Color(1.0,  1.0,  1.0,  1.0)
const _BG_COLOR_SELECTED:    Color = Color(0.0,  0.0,  0.502, 1.0)  # Win95 navy
const _BG_COLOR_NORMAL:      Color = Color(0.753, 0.753, 0.753, 1.0)  # Win95 silver

@onready var _body_area: VBoxContainer = $InnerVBox/BodyArea

var _upgrades:      Array[Dictionary] = []
var _selected:      int = 0
var _row_nodes:     Array[PanelContainer] = []

func _ready() -> void:
	visible = false

# Appends a new upgrade offer and shows the column.
func add_upgrade(data: Dictionary) -> void:
	_upgrades.append(data)
	_build_row(data, _upgrades.size() - 1)
	if _selected >= _upgrades.size():
		_selected = 0
	_refresh_selection()
	visible = true
	print("[UpgradeColumn] add_upgrade id=%s — %d pending" % [data.get("id", "?"), _upgrades.size()])
	upgrade_count_changed.emit(_upgrades.size())

func is_empty() -> bool:
	return _upgrades.is_empty()

func move_selection(delta: int) -> void:
	if _upgrades.is_empty():
		return
	_selected = clamp(_selected + delta, 0, _upgrades.size() - 1)
	_refresh_selection()

func pick_focused() -> void:
	_pick(_selected)

# --- internal ---

func _build_row(data: Dictionary, index: int) -> void:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = SIZE_FILL
	pc.mouse_filter = MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = _BG_COLOR_NORMAL
	pc.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = data.get("label", "?")
	label.add_theme_color_override("font_color", _LABEL_COLOR_NORMAL)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	pc.add_child(label)
	_body_area.add_child(pc)
	_row_nodes.append(pc)

	# Capture index in closure for click handler.
	var captured_index := index
	pc.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_pick(captured_index)
	)

func _refresh_selection() -> void:
	for i in _row_nodes.size():
		var pc := _row_nodes[i]
		var style := pc.get_theme_stylebox("panel") as StyleBoxFlat
		var label := pc.get_child(0) as Label
		if i == _selected:
			style.bg_color = _BG_COLOR_SELECTED
			label.add_theme_color_override("font_color", _LABEL_COLOR_SELECTED)
		else:
			style.bg_color = _BG_COLOR_NORMAL
			label.add_theme_color_override("font_color", _LABEL_COLOR_NORMAL)

func _pick(index: int) -> void:
	if index < 0 or index >= _upgrades.size():
		return
	var data := _upgrades[index]
	var uid: String = data.get("id", "")
	print("[UpgradeColumn] picked id=%s" % uid)

	_upgrades.remove_at(index)
	_row_nodes[index].queue_free()
	_row_nodes.remove_at(index)

	# Re-wire click handlers — indices above the removed one shift down by 1.
	for i in range(index, _row_nodes.size()):
		var pc := _row_nodes[i]
		# Disconnect all existing gui_input signals, then reconnect with new index.
		for connection in pc.gui_input.get_connections():
			pc.gui_input.disconnect(connection["callable"])
		var captured_i := i
		pc.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_pick(captured_i)
		)

	_selected = clamp(_selected, 0, max(0, _upgrades.size() - 1))
	if not _upgrades.is_empty():
		_refresh_selection()
	else:
		visible = false
		print("[UpgradeColumn] all upgrades picked — hiding column")

	upgrade_count_changed.emit(_upgrades.size())
	upgrade_picked.emit(uid)
