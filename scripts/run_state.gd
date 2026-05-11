extends Node

signal round_started(round_num: int, target: int, turns_left: int)
signal round_score_changed(round_score: int, target: int)
signal turns_left_changed(turns_left: int)
signal round_won(round_num: int, round_score: int, target: int)
signal game_over(final_round: int, total_score: int)

const TURNS_PER_ROUND: int = 3

var current_round: int   = 1
var round_score:   int   = 0
var total_score:   int   = 0
var target_score:  int   = 20
var turns_left:    int   = TURNS_PER_ROUND
var is_game_over:  bool  = false
var history:       Array = []

var _t_prev: float = 0.0
var _t_curr: float = 20.0

func reset() -> void:
	current_round = 1
	round_score   = 0
	total_score   = 0
	turns_left    = TURNS_PER_ROUND
	is_game_over  = false
	history.clear()
	_t_prev      = 0.0
	_t_curr      = 20.0
	target_score = 20
	round_started.emit(current_round, target_score, turns_left)

func register_turn_score(points: int) -> void:
	round_score += points
	total_score += points
	turns_left  -= 1
	round_score_changed.emit(round_score, target_score)
	turns_left_changed.emit(turns_left)
	if round_score >= target_score:
		_advance_round()
	elif turns_left <= 0:
		is_game_over = true
		game_over.emit(current_round, total_score)

func _advance_round() -> void:
	history.append({"round": current_round, "score": round_score, "target": target_score})
	round_won.emit(current_round, round_score, target_score)
	current_round += 1
	round_score    = 0
	turns_left     = TURNS_PER_ROUND
	if current_round == 2:
		_t_prev      = _t_curr
		_t_curr      = 30.0
		target_score = 30
	else:
		var next := _t_curr + _t_prev / 2.0
		_t_prev      = _t_curr
		_t_curr      = next
		target_score = int(next)
	round_started.emit(current_round, target_score, turns_left)
