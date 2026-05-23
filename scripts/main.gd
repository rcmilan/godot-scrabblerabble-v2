# res://scripts/main.gd
extends Control

const WORD_BONUS_MULTIPLIER: int = 2

const GLITTER_SCENE   := preload("res://scenes/glitter_emitter.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over_dialog.tscn")

@onready var board:            Board  = %Board
@onready var rack:             Rack   = %Rack
@onready var score_label:      Label  = %ScoreLabel
@onready var tiles_left_label: Label  = %TilesLeftLabel
@onready var end_turn_button:  Button = %EndTurnButton

var pending_cells: Array[BoardCell] = []
var cursor:        Vector2i = Vector2i(0, 0)

func _ready() -> void:
	add_to_group("main")
	randomize()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	cursor = Vector2i(3, 3)
	board.focus_cell(cursor)
	board.cell_focused.connect(_on_cell_focused)
	RunState.reset()
	RunState.round_won.connect(_on_round_won)
	RunState.game_over.connect(_on_game_over)
	_update_hud()

func _on_cell_focused(cell: BoardCell) -> void:
	cursor = cell.grid_pos

# ---------- Input ----------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_move_cursor(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_cursor(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_cursor(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(Vector2i(0, 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm_turn"):
		_on_end_turn_pressed()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode >= KEY_A and key_event.keycode <= KEY_Z:
			_try_place_letter_on_cursor(char(key_event.keycode))

func _move_cursor(delta: Vector2i) -> void:
	var new_pos := cursor + delta
	new_pos.x = clamp(new_pos.x, 0, Board.BOARD_SIZE - 1)
	new_pos.y = clamp(new_pos.y, 0, Board.BOARD_SIZE - 1)
	cursor = new_pos
	board.focus_cell(cursor)

func _try_place_letter_on_cursor(letter: String) -> void:
	var cell := board.get_cell(cursor)
	if cell == null or not cell.is_empty():
		return
	var tile := rack.find_tile_with_letter(letter)
	if tile == null:
		return
	_place_tile_on_cell(tile, cell)

# ---------- Drag and drop ----------
func on_tile_dropped_on_cell(tile: Tile, cell: BoardCell) -> void:
	if not cell.is_empty():
		return
	_place_tile_on_cell(tile, cell)

func on_tile_returned_to_rack(tile: Tile) -> void:
	var prev_cell := board.get_cell(tile.board_pos)
	if prev_cell:
		prev_cell.clear_pending()
		pending_cells.erase(prev_cell)
	tile.location = "rack"
	tile.board_pos = Vector2i(-1, -1)
	tile.visible = true
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	rack.add_child(tile)
	rack.tiles_in_hand.append(tile)
	_update_hud()

func _place_tile_on_cell(tile: Tile, cell: BoardCell) -> void:
	rack.remove_tile(tile)
	cell.place_tile(tile)
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	add_child(tile)
	tile.visible = false
	pending_cells.append(cell)
	# Re-anchor keyboard focus: removing a tile from the rack HBox can
	# steal focus away from the board cell, breaking arrow-key navigation.
	board.focus_cell(cursor)
	_update_hud()
	if pending_cells.size() >= RunState.tiles_per_turn:
		_on_end_turn_pressed()

# ---------- End of turn ----------
func _on_end_turn_pressed() -> void:
	if pending_cells.is_empty():
		return
	var turn_score := _calculate_turn_score()
	print("[Turn] placed=%d  scored=%d" % [pending_cells.size(), turn_score])
	if turn_score > 0:
		for c: BoardCell in pending_cells:
			_spawn_glitter_at(c)
	for c in pending_cells:
		c.lock_pending()
	pending_cells.clear()
	RunState.register_turn_score(turn_score)
	if not RunState.is_game_over:
		rack.refill()
		board.focus_cell(cursor)
	_update_hud()

func _spawn_glitter_at(cell: BoardCell) -> void:
	var emitter: GPUParticles2D = GLITTER_SCENE.instantiate()
	add_child(emitter)
	emitter.global_position = cell.global_position + Vector2(cell.size) * 0.5

func _calculate_turn_score() -> int:
	var words_found: Array = []
	var seen_lines: Dictionary = {}

	for cell in pending_cells:
		var horiz := _extract_word_in_direction(cell, Vector2i(1, 0))
		var vert  := _extract_word_in_direction(cell, Vector2i(0, 1))
		if horiz.text.length() >= 2 and not seen_lines.has("H_" + str(horiz.start)):
			words_found.append(horiz)
			seen_lines["H_" + str(horiz.start)] = true
		if vert.text.length() >= 2 and not seen_lines.has("V_" + str(vert.start)):
			words_found.append(vert)
			seen_lines["V_" + str(vert.start)] = true

	var total := 0
	for w in words_found:
		var word_points := 0
		for letter in (w.text as String):
			word_points += GameData.score_for_letter(letter)
		if GameData.is_valid_word(w.text):
			word_points *= WORD_BONUS_MULTIPLIER
			print("VALID:   %s = %d points" % [w.text, word_points])
		else:
			print("invalid: %s = %d points (no bonus)" % [w.text, word_points])
		total += word_points
	return total

func _extract_word_in_direction(cell: BoardCell, dir: Vector2i) -> Dictionary:
	var start_pos := cell.grid_pos
	while true:
		var prev := start_pos - dir
		var prev_cell := board.get_cell(prev)
		if prev_cell == null or prev_cell.get_letter() == "":
			break
		start_pos = prev
	var text := ""
	var p := start_pos
	while true:
		var c := board.get_cell(p)
		if c == null or c.get_letter() == "":
			break
		text += c.get_letter()
		p += dir
	return {"text": text, "start": start_pos}

func _update_hud() -> void:
	score_label.text      = "Total: %d  |  Round %d" % [RunState.total_score, RunState.current_round]
	tiles_left_label.text = "Progress: %d / %d  |  Turns left: %d  |  Tiles/turn: %d" % [
		RunState.round_score, RunState.target_score,
		RunState.turns_left, RunState.tiles_per_turn]

func _on_round_won(_round_num: int, _round_score: int, _target: int) -> void:
	pending_cells.clear()
	board.clear_all()
	var emitter: GPUParticles2D = GLITTER_SCENE.instantiate()
	add_child(emitter)
	emitter.global_position = board.global_position + board.size * 0.5
	_update_hud()

func _on_game_over(final_round: int, final_score: int) -> void:
	_update_hud()
	var dialog: Panel = GAME_OVER_SCENE.instantiate()
	dialog.setup(final_round, final_score)
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	layer.add_child(dialog)
	# Center the dialog. custom_minimum_size is reliable at this point;
	# size is still (0,0) before the first layout pass.
	var vp_size := get_viewport().get_visible_rect().size
	dialog.position = (vp_size - dialog.custom_minimum_size) / 2.0
