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

# Letter distribution and points (from GameData, embedded here for headless mode)
const LETTER_DISTRIBUTION = {
	"A": 9, "B": 2, "C": 2, "D": 4, "E": 12, "F": 2, "G": 3,
	"H": 2, "I": 9, "J": 1, "K": 1, "L": 4, "M": 2, "N": 6,
	"O": 8, "P": 2, "Q": 1, "R": 6, "S": 4, "T": 6, "U": 4,
	"V": 2, "W": 2, "X": 1, "Y": 2, "Z": 1,
}

const LETTER_POINTS = {
	"A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2,
	"H": 4, "I": 1, "J": 8, "K": 5, "L": 1, "M": 3, "N": 1,
	"O": 1, "P": 3, "Q": 10, "R": 1, "S": 1, "T": 1, "U": 1,
	"V": 4, "W": 4, "X": 8, "Y": 4, "Z": 10,
}

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
	for letter in LETTER_DISTRIBUTION.keys():
		for _i in LETTER_DISTRIBUTION[letter]:
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
			word_points += LETTER_POINTS.get(letter.to_upper(), 0)
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
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			board[x][y] = ""

func _advance_round() -> void:
	# Reset round state BEFORE advancing target, so progression is correct.
	current_round += 1
	round_score = 0
	turns_left = TURNS_PER_ROUND
	tiles_per_turn += 1
	if current_round == 2:
		_t_prev = _t_curr
		_t_curr = 30.0
		target_score = 30
	else:
		var next := _t_curr + _t_prev / 2.0
		_t_prev = _t_curr
		_t_curr = next
		target_score = int(next)
	clear_board()
