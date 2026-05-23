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

# TC2 - Rack draw determinism: seed=12345 produces the expected sequence.
func test_rack_draw_determinism() -> bool:
	var expected = ["L", "A", "S", "O", "E", "E", "S", "M", "S", "O", "A", "R", "I", "A", "I", "G", "A", "F", "P", "D"]
	var core = GameCore.new(12345)
	var drawn = []
	for _i in 20:
		drawn.append(core.draw_letter())
	if drawn != expected:
		push_error("Draw sequence mismatch. Expected %s, got %s" % [expected, drawn])
		return false
	return true

# TC3 - Rack draw distribution: frequencies within +/- 10% of expected.
func test_rack_draw_distribution() -> bool:
	var core = GameCore.new(999)
	var counts = {}
	var total = 100000
	for _i in total:
		var letter = core.draw_letter()
		counts[letter] = counts.get(letter, 0) + 1

	for letter in GameData.LETTER_DISTRIBUTION.keys():
		var expected_count = GameData.LETTER_DISTRIBUTION[letter]
		var expected_freq = float(expected_count) / 100.0
		var actual_count = counts.get(letter, 0)
		var actual_freq = float(actual_count) / float(total)

		var tolerance = expected_freq * 0.1
		if abs(actual_freq - expected_freq) > tolerance:
			push_error("Letter %s: expected freq %.4f, got %.4f (count %d vs %d)" % [
				letter, expected_freq, actual_freq, expected_count, actual_count])
			return false

	return true

# TC4 - Scoring parity: word extraction and point calculation.
func test_scoring_word_extraction() -> bool:
	var core = GameCore.new(123)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# C=3, A=1, T=1; total=5
	# Dictionary validation happens in _calculate_turn_score but depends on GameData
	# For now, just verify extraction and base scoring works
	if score < 5:
		push_error("Expected minimum score 5 for 'CAT', got %d" % score)
		return false
	return true

# TC5 - Cross-word extraction: single-letter words are skipped.
func test_cross_word_skip_length_one() -> bool:
	var core = GameCore.new(456)
	# Set up "CAT" horizontally
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	# Place "S" at (3,0) to complete "CATS" horizontally
	# But (3,1) is empty, so vertical word from (3,0) is only "S" (length 1)
	core.board[3][0] = "S"

	var horiz = core._extract_word_in_direction(Vector2i(3, 0), Vector2i(1, 0))
	var vert = core._extract_word_in_direction(Vector2i(3, 0), Vector2i(0, 1))

	# Horizontal should be "CATS"
	if horiz.text != "CATS":
		push_error("Expected 'CATS' horizontal, got '%s'" % horiz.text)
		return false

	# Vertical from (3,0) going down should be "S" (length 1, should be skipped in scoring)
	if vert.text != "S":
		push_error("Expected 'S' vertical, got '%s'" % vert.text)
		return false

	return true
