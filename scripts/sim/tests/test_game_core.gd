class_name TestGameCore
extends RefCounted

const GameCore = preload("res://scripts/sim/game_core.gd")

# TC1 - Constants parity: GameCore constants match the canonical values.
func test_constants_parity() -> bool:
	if GameCore.TURNS_PER_ROUND != 3:
		push_error("TURNS_PER_ROUND: expected 3, got %d" % GameCore.TURNS_PER_ROUND)
		return false
	if GameCore.INITIAL_TILES_PER_TURN != 4:
		push_error("INITIAL_TILES_PER_TURN: expected 4, got %d" % GameCore.INITIAL_TILES_PER_TURN)
		return false
	if GameCore.INITIAL_TARGET_SCORE != 20:
		push_error("INITIAL_TARGET_SCORE: expected 20, got %d" % GameCore.INITIAL_TARGET_SCORE)
		return false
	if GameCore.WORD_BONUS_MULTIPLIER != 2:
		push_error("WORD_BONUS_MULTIPLIER: expected 2, got %d" % GameCore.WORD_BONUS_MULTIPLIER)
		return false
	if GameCore.BOARD_SIZE != 8:
		push_error("BOARD_SIZE: expected 8, got %d" % GameCore.BOARD_SIZE)
		return false
	if GameCore.RACK_SIZE != 7:
		push_error("RACK_SIZE: expected 7, got %d" % GameCore.RACK_SIZE)
		return false
	return true
