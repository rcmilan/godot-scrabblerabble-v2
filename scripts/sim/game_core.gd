class_name GameCore
extends RefCounted

# Pure game logic with no Control or Node dependencies.
# This class duplicates logic from main.gd and run_state.gd.
# See ../README.md for the duplication notice.

# Progression constants (copied from RunState, main.gd, board.gd, rack.gd).
const TURNS_PER_ROUND:        int = 3
const INITIAL_TILES_PER_TURN: int = 4
const INITIAL_TARGET_SCORE:   int = 20
const WORD_BONUS_MULTIPLIER:  int = 2
const BOARD_SIZE:             int = 8
const RACK_SIZE:              int = 7

# Board state: 8x8, indexed [x][y], values are letter strings.
var board: Array = []

# Rack: current letters, length up to 7.
var rack: Array[String] = []

# RNG seeded per game.
var rng: RandomNumberGenerator

# Progression state (mirrors RunState).
var current_round:  int   = 1
var round_score:    int   = 0
var target_score:   int   = INITIAL_TARGET_SCORE
var turns_left:     int   = TURNS_PER_ROUND
var tiles_per_turn: int   = INITIAL_TILES_PER_TURN
var is_game_over:   bool  = false

# Target curve state.
var _t_prev: float = 0.0
var _t_curr: float = float(INITIAL_TARGET_SCORE)

func _init(seed: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	_init_board()
	refill_rack()

func _init_board() -> void:
	board.clear()
	board.resize(BOARD_SIZE)
	for x in BOARD_SIZE:
		board[x] = []
		board[x].resize(BOARD_SIZE)
		for y in BOARD_SIZE:
			board[x][y] = ""

func draw_letter() -> String:
	var bag: Array[String] = []
	for letter in GameData.LETTER_DISTRIBUTION.keys():
		for _i in GameData.LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[rng.randi() % bag.size()]

func refill_rack() -> void:
	while rack.size() < RACK_SIZE:
		var letter := draw_letter()
		rack.append(letter)

func is_cell_empty(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= BOARD_SIZE or pos.y < 0 or pos.y >= BOARD_SIZE:
		return false
	return board[pos.x][pos.y] == ""

func place_pending(letter: String, pos: Vector2i) -> bool:
	if not is_cell_empty(pos):
		return false
	if letter not in rack:
		return false
	board[pos.x][pos.y] = letter
	rack.erase(letter)
	return true

func end_turn(pending_positions: Array) -> int:
	var turn_score := _calculate_turn_score(pending_positions)
	round_score += turn_score
	turns_left -= 1
	if round_score >= target_score:
		_advance_round()
	elif turns_left <= 0:
		is_game_over = true
	refill_rack()
	return turn_score

func _calculate_turn_score(pending_positions: Array) -> int:
	var words_found: Array = []
	var seen_lines: Dictionary = {}

	for pos in pending_positions:
		var horiz := _extract_word_in_direction(pos, Vector2i(1, 0))
		var vert := _extract_word_in_direction(pos, Vector2i(0, 1))
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
		total += word_points
	return total

func _extract_word_in_direction(pos: Vector2i, dir: Vector2i) -> Dictionary:
	var start_pos := pos
	while true:
		var prev := start_pos - dir
		if prev.x < 0 or prev.x >= BOARD_SIZE or prev.y < 0 or prev.y >= BOARD_SIZE:
			break
		if board[prev.x][prev.y] == "":
			break
		start_pos = prev
	var text := ""
	var p := start_pos
	while true:
		if p.x < 0 or p.x >= BOARD_SIZE or p.y < 0 or p.y >= BOARD_SIZE:
			break
		if board[p.x][p.y] == "":
			break
		text += board[p.x][p.y]
		p += dir
	return {"text": text, "start": start_pos}

func clear_board() -> void:
	# TODO: implement
	pass

func _advance_round() -> void:
	# TODO: implement target curve and progression
	pass
