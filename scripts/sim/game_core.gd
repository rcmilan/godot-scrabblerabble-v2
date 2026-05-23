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
	# TODO: implement weighted random draw matching Rack._draw_random_letter
	return ""

func refill_rack() -> void:
	# TODO: implement rack refill matching Rack.refill
	pass

func is_cell_empty(pos: Vector2i) -> bool:
	# TODO: implement
	return false

func place_pending(letter: String, pos: Vector2i) -> bool:
	# TODO: implement
	return false

func end_turn(pending_positions: Array) -> int:
	# TODO: implement scoring and progression
	return 0

func clear_board() -> void:
	# TODO: implement
	pass

func _advance_round() -> void:
	# TODO: implement target curve and progression
	pass
