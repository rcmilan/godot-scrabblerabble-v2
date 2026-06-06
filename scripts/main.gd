# res://scripts/main.gd
extends Control

const WORD_BONUS_MULTIPLIER: int = 2

const GLITTER_SCENE          := preload("res://scenes/glitter_emitter.tscn")
const GAME_OVER_SCENE        := preload("res://scenes/game_over_dialog.tscn")
const ROUND_TRANSITION_SCENE := preload("res://scenes/round_transition.tscn")
const UPGRADE_DIALOG_SCENE   := preload("res://scenes/upgrade_dialog.tscn")

const WORD_SEARCH_STRATEGY      := preload("res://scripts/sim/strategies/word_search_strategy.gd")
const GREEDY_STRATEGY           := preload("res://scripts/sim/strategies/greedy_strategy.gd")
const RANDOM_STRATEGY           := preload("res://scripts/sim/strategies/random_strategy.gd")
const DIAGONAL_CLUSTER_STRATEGY := preload("res://scripts/sim/strategies/diagonal_cluster_strategy.gd")
const HYBRID_WORD_DIAGONAL_STRATEGY := preload("res://scripts/sim/strategies/hybrid_word_diagonal_strategy.gd")
const CORNER_SPIRAL_STRATEGY := preload("res://scripts/sim/strategies/corner_spiral_strategy.gd")

const AUTOPLAY_STEP_MS: int = 200

var _autoplay_active: bool = false

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
	_maybe_start_autoplay()

func _on_cell_focused(cell: BoardCell) -> void:
	cursor = cell.grid_pos

# ---------- Input ----------
func _unhandled_input(event: InputEvent) -> void:
	if RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading:
		return

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
	if RunState.is_transitioning or RunState.is_upgrading or not cell.is_empty():
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
		if GameData.is_valid_word(w.text):
			# Full word is valid - score it with word bonus
			var word_points := _score_word(w)
			var mods_str := _get_modifiers_str(w)
			print("VALID:   %s = %d points (modifiers: %s)" % [w.text, word_points, mods_str])
			total += word_points
		else:
			# Full word is invalid - try to find valid sub-words
			var sub_words_found := false
			# Try all possible sub-words (length 2+)
			for start_idx in range(w.text.length() - 1):
				for end_idx in range(start_idx + 2, w.text.length() + 1):
					var sub_word: String = w.text.substr(start_idx, end_idx - start_idx)
					if GameData.is_valid_word(sub_word):
						sub_words_found = true
						# Calculate score for sub-word
						var sub_points := 0
						var sub_mods: Array = []
						for i in range(start_idx, end_idx):
							var ch: String = w.text[i]
							var cell: BoardCell = w.cells[i]
							var letter_pts: int = GameData.score_for_letter(ch)
							if cell.get_modifier() == GameData.MOD_2X:
								letter_pts *= 2
								sub_mods.append("2x@%d" % (i - start_idx))
							sub_points += letter_pts
						# Apply word bonus if at least one new tile in sub-word
						var has_new_tile := false
						for i in range(start_idx, end_idx):
							if w.cells[i] in pending_cells:
								has_new_tile = true
								break
						if has_new_tile:
							sub_points *= WORD_BONUS_MULTIPLIER
						var mods_str := ", ".join(sub_mods) if sub_mods.size() > 0 else "none"
						print("VALID:   %s = %d points (modifiers: %s)" % [sub_word, sub_points, mods_str])
						total += sub_points
			# If no valid sub-words, score just the letter values (no word bonus)
			if not sub_words_found:
				var letter_points := 0
				var mods_parts: Array = []
				for i in (w.text as String).length():
					var ch: String = w.text[i]
					var cell: BoardCell = w.cells[i]
					var letter_pts: int = GameData.score_for_letter(ch)
					if cell.get_modifier() == GameData.MOD_2X:
						letter_pts *= 2
						mods_parts.append("2x@%d" % i)
					letter_points += letter_pts
				var mods_str := ", ".join(mods_parts) if mods_parts.size() > 0 else "none"
				print("invalid: %s = %d points (modifiers: %s)" % [w.text, letter_points, mods_str])
				total += letter_points
	return total

func _score_word(w: Dictionary) -> int:
	var word_points := 0
	var mods_parts: Array = []
	for i in (w.text as String).length():
		var ch: String = (w.text as String)[i]
		var cell: BoardCell = w.cells[i]
		var letter_pts: int = GameData.score_for_letter(ch)
		if cell.get_modifier() == GameData.MOD_2X:
			letter_pts *= 2
			mods_parts.append("2x@%d" % i)
		word_points += letter_pts
	word_points *= WORD_BONUS_MULTIPLIER
	return word_points

func _get_modifiers_str(w: Dictionary) -> String:
	var mods_parts: Array = []
	for i in (w.text as String).length():
		var cell: BoardCell = w.cells[i]
		if cell.get_modifier() == GameData.MOD_2X:
			mods_parts.append("2x@%d" % i)
	return ", ".join(mods_parts) if mods_parts.size() > 0 else "none"

func _extract_word_in_direction(cell: BoardCell, dir: Vector2i) -> Dictionary:
	var start_pos := cell.grid_pos
	while true:
		var prev := start_pos - dir
		var prev_cell := board.get_cell(prev)
		if prev_cell == null or prev_cell.get_letter() == "":
			break
		start_pos = prev
	var text := ""
	var cells_arr: Array = []
	var p := start_pos
	while true:
		var c := board.get_cell(p)
		if c == null or c.get_letter() == "":
			break
		text += c.get_letter()
		cells_arr.append(c)
		p += dir
	return {"text": text, "start": start_pos, "cells": cells_arr}

func _update_hud() -> void:
	score_label.text      = "Score: %d  |  Round %d  |  Target: %d" % [
		RunState.round_score, RunState.current_round, RunState.target_score]
	tiles_left_label.text = "Turns left: %d  |  Tiles/turn: %d" % [
		RunState.turns_left, RunState.tiles_per_turn]

func _on_round_won(round_num: int, _round_score: int, _target: int) -> void:
	pending_cells.clear()
	board.clear_all()
	var emitter: GPUParticles2D = GLITTER_SCENE.instantiate()
	add_child(emitter)
	emitter.global_position = board.global_position + board.size * 0.5
	_update_hud()
	RunState.is_transitioning = true
	var transition: CanvasLayer = ROUND_TRANSITION_SCENE.instantiate()
	add_child(transition)
	transition.finished.connect(_on_transition_finished)
	transition.play(round_num)

func _on_transition_finished() -> void:
	RunState.is_transitioning = false
	if RunState.is_upgrade_due():
		_show_upgrade_dialog()
	else:
		board.focus_cell(cursor)

func _show_upgrade_dialog() -> void:
	var upgrades: Array[Dictionary] = [
		{"id": GameData.MOD_2X, "label": "2x Tile", "desc": "+1 guaranteed 2x tile"},
	]
	RunState.is_upgrading = true
	print("[UpgradeDialog] upgrade offered — round %d" % RunState.current_round)

	var dialog: Panel = UPGRADE_DIALOG_SCENE.instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(dialog)

	# Center dialog; use custom_minimum_size since size is (0,0) before first layout pass.
	var vp_size := get_viewport().get_visible_rect().size
	dialog.position = (vp_size - dialog.custom_minimum_size) / 2.0

	dialog.populate(upgrades)
	dialog.focus_first()

	dialog.upgrade_picked.connect(func(id: String) -> void:
		layer.queue_free()
		RunState.is_upgrading = false
		RunState.add_to_build(id)
		rack.refill()
		board.focus_cell(cursor)
		_update_hud()
	)
	dialog.skipped.connect(func() -> void:
		layer.queue_free()
		RunState.is_upgrading = false
		board.focus_cell(cursor)
	)

	if _autoplay_active:
		_autoplay_pick_upgrade_dialog(dialog)

func _autoplay_pick_upgrade_dialog(dialog: UpgradeDialog) -> void:
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(dialog):
		dialog.upgrade_picked.emit(GameData.MOD_2X)

func _on_game_over(final_round: int, final_round_score: int, final_target: int) -> void:
	_autoplay_active = false
	_update_hud()
	var dialog: Panel = GAME_OVER_SCENE.instantiate()
	dialog.setup(final_round, final_round_score, final_target)
	var layer := CanvasLayer.new()
	# Below the CRT overlay (layer 100) so scanlines/vignette draw over the dialog.
	layer.layer = 50
	add_child(layer)
	layer.add_child(dialog)
	# Center the dialog. custom_minimum_size is reliable at this point;
	# size is still (0,0) before the first layout pass.
	var vp_size := get_viewport().get_visible_rect().size
	dialog.position = (vp_size - dialog.custom_minimum_size) / 2.0

# ---------- Autoplay ----------
func _maybe_start_autoplay() -> void:
	var strategy_name := _autoplay_strategy_arg()
	if strategy_name == "":
		return
	var strategy = _build_strategy(strategy_name)
	if strategy == null:
		print("[Autoplay] unknown strategy: %s" % strategy_name)
		return
	_autoplay_active = true
	print("[Autoplay] starting with strategy=%s, step=%dms" % [strategy_name, AUTOPLAY_STEP_MS])
	_run_autoplay(strategy)

func _autoplay_strategy_arg() -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--autoplay="):
			return raw.trim_prefix("--autoplay=")
		if raw == "--autoplay":
			return "word_search"
	return ""

func _build_strategy(name: String):
	match name:
		"word_search":      return WORD_SEARCH_STRATEGY.new()
		"greedy":           return GREEDY_STRATEGY.new()
		"random":           return RANDOM_STRATEGY.new()
		"diagonal_cluster": return DIAGONAL_CLUSTER_STRATEGY.new()
		"hybrid_word_diagonal": return HYBRID_WORD_DIAGONAL_STRATEGY.new()
		"corner_spiral":    return CORNER_SPIRAL_STRATEGY.new()
		_:                  return null

func _run_autoplay(strategy) -> void:
	# Tiny adapter exposing the GameCore shape that strategies expect,
	# but reading live state from Board/Rack/RunState.
	var adapter := _AutoplayAdapter.new(board, rack)
	while _autoplay_active and not RunState.is_game_over:
		if RunState.is_transitioning or RunState.is_upgrading:
			await get_tree().create_timer(0.2).timeout
			continue
		adapter.refresh(RunState.tiles_per_turn)
		var moves: Array = strategy.pick_moves(adapter)
		if moves.is_empty():
			print("[Autoplay] strategy returned no moves — ending turn")
			# Force a turn end if anything is pending, otherwise bail.
			if pending_cells.size() > 0:
				_on_end_turn_pressed()
			else:
				_autoplay_active = false
				break
			await get_tree().create_timer(AUTOPLAY_STEP_MS / 1000.0).timeout
			continue
		var placed_any := false
		for move in moves:
			if not _autoplay_active or RunState.is_game_over or RunState.is_transitioning or RunState.is_upgrading:
				break
			var cell := board.get_cell(move.pos)
			if cell == null or not cell.is_empty():
				continue
			var tile := rack.find_tile_with_letter(move.letter)
			if tile == null:
				continue
			_place_tile_on_cell(tile, cell)
			placed_any = true
			await get_tree().create_timer(AUTOPLAY_STEP_MS / 1000.0).timeout
		# If we placed fewer than tiles_per_turn (e.g. strategy short word),
		# force the turn to end so the loop advances.
		if placed_any and pending_cells.size() > 0:
			_on_end_turn_pressed()
			await get_tree().create_timer(AUTOPLAY_STEP_MS / 1000.0).timeout
		elif not placed_any:
			print("[Autoplay] no valid placement this turn — stopping")
			_autoplay_active = false
			break

class _AutoplayAdapter:
	extends RefCounted
	const BOARD_SIZE: int = 8
	var board: Array = []
	var rack: Array = []
	var tiles_per_turn: int = 0
	var rng: RandomNumberGenerator
	var _board_node
	var _rack_node
	func _init(b, r) -> void:
		_board_node = b
		_rack_node = r
		rng = RandomNumberGenerator.new()
		rng.randomize()
	func refresh(current_tiles_per_turn: int) -> void:
		tiles_per_turn = current_tiles_per_turn
		board.clear()
		board.resize(BOARD_SIZE)
		for x in BOARD_SIZE:
			board[x] = []
			board[x].resize(BOARD_SIZE)
			for y in BOARD_SIZE:
				var cell = _board_node.get_cell(Vector2i(x, y))
				board[x][y] = cell.get_letter() if cell else ""
		rack.clear()
		for tile in _rack_node.tiles_in_hand:
			rack.append({"letter": tile.letter, "modifier": tile.modifier})
	func rack_letters() -> Array:
		var out: Array = []
		for t in rack:
			out.append(t.letter)
		return out
	func is_cell_empty(pos: Vector2i) -> bool:
		if pos.x < 0 or pos.x >= BOARD_SIZE or pos.y < 0 or pos.y >= BOARD_SIZE:
			return false
		return board[pos.x][pos.y] == ""
