extends Node

signal round_started(round_num: int, target: int, turns_left: int)
signal round_score_changed(round_score: int, target: int)
signal turns_left_changed(turns_left: int)
signal round_won(round_num: int, round_score: int, target: int)
signal game_over(final_round: int, final_round_score: int, final_target: int)

const TURNS_PER_ROUND:        int = 3
const INITIAL_TILES_PER_TURN: int = 4
const INITIAL_TARGET_SCORE:   int = 20

var current_round:  int   = 1
var round_score:    int   = 0
var target_score:   int   = INITIAL_TARGET_SCORE
var turns_left:     int   = TURNS_PER_ROUND
var tiles_per_turn: int   = INITIAL_TILES_PER_TURN
var is_game_over:   bool  = false
var is_transitioning: bool = false
var history:        Array = []

var _t_prev: float = 0.0
var _t_curr: float = float(INITIAL_TARGET_SCORE)

func reset() -> void:
	current_round  = 1
	round_score    = 0
	turns_left     = TURNS_PER_ROUND
	tiles_per_turn = INITIAL_TILES_PER_TURN
	is_game_over   = false
	is_transitioning = false
	history.clear()
	_t_prev      = 0.0
	_t_curr      = float(INITIAL_TARGET_SCORE)
	target_score = INITIAL_TARGET_SCORE
	print("[RunState] reset — round 1, target %d, %d tiles/turn" % [target_score, tiles_per_turn])
	round_started.emit(current_round, target_score, turns_left)

func register_turn_score(points: int) -> void:
	round_score += points
	turns_left  -= 1
	round_score_changed.emit(round_score, target_score)
	turns_left_changed.emit(turns_left)
	if round_score >= target_score:
		_advance_round()
	elif turns_left <= 0:
		is_game_over = true
		print("[RunState] game over — round %d, scored %d / %d" % [current_round, round_score, target_score])
		game_over.emit(current_round, round_score, target_score)

func _advance_round() -> void:
	var won_round    := current_round
	var won_score    := round_score
	var won_target   := target_score
	history.append({"round": won_round, "score": won_score, "target": won_target})
	# Reset round state *before* emitting so handlers see the new round.
	current_round  += 1
	round_score     = 0
	turns_left      = TURNS_PER_ROUND
	tiles_per_turn += 1
	if current_round == 2:
		_t_prev      = _t_curr
		_t_curr      = 30.0
		target_score = 30
	else:
		var next := _t_curr + _t_prev / 2.0
		_t_prev      = _t_curr
		_t_curr      = next
		target_score = int(next)
	print("[RunState] round %d won (%d / %d) — now round %d, target %d, %d tiles/turn" % [
		won_round, won_score, won_target, current_round, target_score, tiles_per_turn])
	round_won.emit(won_round, won_score, won_target)
	round_started.emit(current_round, target_score, turns_left)
