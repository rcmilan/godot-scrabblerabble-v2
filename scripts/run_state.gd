extends Node

signal round_started(round_num: int, target: int, turns_left: int)
signal round_score_changed(round_score: int, target: int)
signal turns_left_changed(turns_left: int)
signal discards_left_changed(discards_left: int)
signal round_won(round_num: int, round_score: int, target: int)
signal game_over(final_round: int, final_round_score: int, final_target: int)
signal run_finished(won: bool, final_round: int, total: int)

enum Mode { EASY, MEDIUM, HARD, ENDLESS }

const TURNS_PER_ROUND:        int = 3
const INITIAL_TILES_PER_TURN: int = 4
const INITIAL_TARGET_SCORE:   int = 20
const UPGRADE_EVERY_N_ROUNDS: int = 3
const DISCARDS_PER_ROUND:     int = 3
const ROUNDS_PER_DIFFICULTY:  int = 5
const DIFFICULTY_TARGETS := {
	Mode.EASY:   [12, 18, 26, 34, 44],
	Mode.MEDIUM: [16, 24, 34, 46, 60],
	Mode.HARD:   [25, 38, 52, 70, 92],
}

var current_round:  int   = 1
var round_score:    int   = 0
var target_score:   int   = INITIAL_TARGET_SCORE
var turns_left:     int   = TURNS_PER_ROUND
var tiles_per_turn: int   = INITIAL_TILES_PER_TURN
var is_game_over:   bool  = false
var is_transitioning: bool = false
var is_upgrading:   bool  = false
var discards_left:  int   = DISCARDS_PER_ROUND
var autoplay_run_completed: bool = false
var history:        Array = []
var modifier_build: Dictionary = {}   # { "2x": int, ... }  keyed by mod constant
var letter_modifiers: Dictionary = {}  # { "A": "2x", ... }  maps letter → modifier
var mode:           int   = Mode.ENDLESS
var total_score:    int   = 0
var session_high_scores := { Mode.EASY: 0, Mode.MEDIUM: 0, Mode.HARD: 0 }

var _t_prev: float = 0.0
var _t_curr: float = float(INITIAL_TARGET_SCORE)

func reset() -> void:
	current_round  = 1
	round_score    = 0
	total_score    = 0
	turns_left     = TURNS_PER_ROUND
	tiles_per_turn = INITIAL_TILES_PER_TURN
	is_game_over   = false
	is_transitioning = false
	is_upgrading   = false
	history.clear()
	modifier_build.clear()
	letter_modifiers.clear()
	_t_prev      = 0.0
	_t_curr      = float(INITIAL_TARGET_SCORE)
	if is_difficulty_mode():
		target_score = DIFFICULTY_TARGETS[mode][0]
	else:
		target_score = INITIAL_TARGET_SCORE
	discards_left = DISCARDS_PER_ROUND
	discards_left_changed.emit(discards_left)
	print("[RunState] reset — %s, round 1, target %d, %d tiles/turn" % [mode_name(), target_score, tiles_per_turn])
	round_started.emit(current_round, target_score, turns_left)

func is_upgrade_due() -> bool:
	return current_round > 1 and (current_round - 1) % UPGRADE_EVERY_N_ROUNDS == 0

func is_difficulty_mode() -> bool:
	return mode != Mode.ENDLESS

func mode_name() -> String:
	match mode:
		Mode.EASY:   return "Easy"
		Mode.MEDIUM: return "Medium"
		Mode.HARD:   return "Hard"
		_:           return "Endless"

func record_high_score(total: int) -> bool:
	if not is_difficulty_mode():
		return false
	var prev: int = session_high_scores[mode]
	var is_new := total > prev
	if is_new:
		session_high_scores[mode] = total
	return is_new

func _finish_run(won: bool) -> void:
	is_game_over = true
	print("[RunState] run finished — %s, round %d, total %d" % [
		"won" if won else "lost", current_round, total_score])
	run_finished.emit(won, current_round, total_score)

func add_to_build(mod: String) -> void:
	modifier_build[mod] = modifier_build.get(mod, 0) + 1
	print("[RunState] build += %s (total %d)" % [mod, modifier_build[mod]])

func set_letter_modifier(letter: String, mod: String) -> void:
	letter_modifiers[letter] = mod
	print("[RunState] letter modifier set — %s → %s" % [letter, mod])

func use_discard() -> void:
	discards_left -= 1
	print("[Discard] used — %d left" % discards_left)
	discards_left_changed.emit(discards_left)

func register_turn_score(points: int) -> void:
	total_score += points
	round_score += points
	turns_left  -= 1
	round_score_changed.emit(round_score, target_score)
	turns_left_changed.emit(turns_left)
	if round_score >= target_score:
		if is_difficulty_mode() and current_round >= ROUNDS_PER_DIFFICULTY:
			_finish_run(true)
		else:
			_advance_round()
	elif turns_left <= 0:
		if is_difficulty_mode():
			_finish_run(false)
		else:
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
	discards_left = DISCARDS_PER_ROUND
	discards_left_changed.emit(discards_left)
	if is_difficulty_mode():
		target_score = DIFFICULTY_TARGETS[mode][current_round - 1]
	elif current_round == 2:
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
