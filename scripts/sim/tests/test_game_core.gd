class_name TestGameCore
extends RefCounted

const GameCore = preload("res://scripts/sim/game_core.gd")

# Random premium layout would break hand-computed sums — zero it for tests
# that assert exact scores unrelated to premiums.
func _zero_premiums(core) -> void:
	for x in GameCore.BOARD_SIZE:
		for y in GameCore.BOARD_SIZE:
			core.board_premiums[x][y] = GameCore.PREM_NONE

# TC1 - Constants parity: GameCore constants match the canonical values.
func test_constants_parity() -> bool:
	if GameCore.TURNS_PER_ROUND != 3:
		push_error("TURNS_PER_ROUND: expected 3, got %d" % GameCore.TURNS_PER_ROUND)
		return false
	if GameCore.INITIAL_TILES_PER_TURN != 4:
		push_error("INITIAL_TILES_PER_TURN: expected 4, got %d" % GameCore.INITIAL_TILES_PER_TURN)
		return false
	if GameCore.INITIAL_TARGET_SCORE != 32:
		push_error("INITIAL_TARGET_SCORE: expected 32, got %d" % GameCore.INITIAL_TARGET_SCORE)
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
# Re-pinned when _reroll_premiums() started consuming rng draws before the first
# tile draw — the sequence shifts, determinism does not.
func test_rack_draw_determinism() -> bool:
	var expected = ["H", "R", "X", "T", "T", "Q", "L", "R", "E", "L", "O", "I", "W", "B", "I", "T", "O", "P", "T", "H"]
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
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# Whole-board scoring counts every valid sub-word of the run "CAT":
	#   AT  = (1+1)*2 = 4
	#   CAT = (3+1+1)*2 = 10
	# total = 14
	if score != 14:
		push_error("Expected 14 for 'CAT' (AT + CAT), got %d" % score)
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

# TC6 - Target curve parity: rounds 1-4 produce expected target sequence.
func test_target_curve_parity() -> bool:
	var core = GameCore.new(999)
	var expected_targets = [32, 40, 52, 68]

	for round_num in range(4):
		if core.target_score != expected_targets[round_num]:
			push_error("Round %d: expected target %d, got %d" % [
				round_num + 1, expected_targets[round_num], core.target_score])
			return false
		# Simulate winning the round
		core.round_score = core.target_score + 1
		core._advance_round()

	return true

# TC7 - Round advance ordering: round resets BEFORE target advances.
func test_round_advance_ordering() -> bool:
	var core = GameCore.new(888)
	# Start: round 1, target 20, turns_left 3, tiles_per_turn 4
	if core.current_round != 1 or core.tiles_per_turn != 4:
		push_error("Initial state wrong")
		return false

	# Trigger round advance
	core.round_score = 25
	core.turns_left = 1
	core._advance_round()

	# After advance: round 2, target 40, turns_left 3, tiles_per_turn 5
	if core.current_round != 2:
		push_error("Round didn't advance")
		return false
	if core.target_score != 40:
		push_error("Target should be 40, got %d" % core.target_score)
		return false
	if core.turns_left != 3:
		push_error("Turns should reset to 3, got %d" % core.turns_left)
		return false
	if core.tiles_per_turn != 5:
		push_error("tiles_per_turn should be 5, got %d" % core.tiles_per_turn)
		return false

	return true

# TC8 - Game over trigger: missing target on last turn sets game over.
func test_game_over_trigger() -> bool:
	var core = GameCore.new(777)
	core.turns_left = 1
	core.round_score = 5  # Below target of 20
	core.end_turn([])  # Score 0, stay below target, turns becomes 0
	if not core.is_game_over:
		push_error("Game should be over after last turn")
		return false
	return true

# TC9 - Letter modifier on refill: tiles matching the chosen letter carry MOD_2X.
func test_modifier_guarantee_on_refill() -> bool:
	# Use letter "A" (high frequency) — across 20 seeds we expect at least some hits.
	var hits_found := false
	for seed in range(20):
		var core = GameCore.new(seed, {}, {"A": GameCore.MOD_2X})
		for t in core.rack:
			if t.letter == "A":
				if t.modifier != GameCore.MOD_2X:
					push_error("TC9 seed %d: tile A should have MOD_2X, got '%s'" % [seed, t.modifier])
					return false
				hits_found = true
			else:
				if t.modifier == GameCore.MOD_2X:
					push_error("TC9 seed %d: tile %s should NOT have MOD_2X" % [seed, t.letter])
					return false
	# "A" is high-frequency so we expect at least one hit across 20 seeds.
	if not hits_found:
		push_error("TC9: no 'A' tile appeared in any of 20 seeded racks — unexpected")
		return false
	return true

# TC10 - Modifier promotion picks lowest-value letter.
func test_modifier_promotion_picks_lowest() -> bool:
	var core = GameCore.new(100)
	# Bypass refill_rack, write rack directly with known letters.
	# T at index 3 is the only 1-pt tile → must be promoted.
	core.rack = [
		{"letter": "B", "modifier": GameCore.MOD_NONE},  # 3 pts
		{"letter": "C", "modifier": GameCore.MOD_NONE},  # 3 pts
		{"letter": "D", "modifier": GameCore.MOD_NONE},  # 2 pts
		{"letter": "T", "modifier": GameCore.MOD_NONE},  # 1 pt  <- lowest
		{"letter": "M", "modifier": GameCore.MOD_NONE},  # 3 pts
		{"letter": "V", "modifier": GameCore.MOD_NONE},  # 4 pts
		{"letter": "Q", "modifier": GameCore.MOD_NONE},  # 10 pts
	]
	core._ensure_modifier_count_in_rack(GameCore.MOD_2X, 1)
	if core.rack[3].modifier != GameCore.MOD_2X:
		push_error("TC10: expected T (index 3) to be promoted, rack=%s" % str(core.rack))
		return false
	var count := 0
	for t in core.rack:
		if t.modifier == GameCore.MOD_2X:
			count += 1
	if count != 1:
		push_error("TC10: expected exactly 1 MOD_2X tile, got %d" % count)
		return false
	return true

# TC11 - Modifier scoring doubles letter contribution.
func test_modifier_scoring_doubles_letter() -> bool:
	var core = GameCore.new(200)
	_zero_premiums(core)
	# Place CAT horizontally: C=3, A=1, T=1
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[0][0] = GameCore.MOD_2X  # C doubled: 6 instead of 3
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# Whole-board scoring counts both valid sub-words of "CAT", C doubled:
	#   AT  = (1+1)*2 = 4
	#   CAT = (3*2 + 1 + 1)*2 = 16
	# total = 20  (without the modifier it would be 4 + 10 = 14)
	if score != 20:
		push_error("TC11: expected 20 for CAT with C=MOD_2X, got %d" % score)
		return false
	return true

# TC12 - A run with no valid sub-words scores 0 (only valid words count now).
func test_invalid_word_scores_zero() -> bool:
	# ZQX has no valid length>=2 substring, so it scores nothing regardless of
	# modifiers. The old consolation "bare letter" fallback is gone — score and
	# highlight mirror each other, and gibberish neither glows nor scores.
	for w in ["ZQ", "QX", "ZQX"]:
		if GameCore.is_valid_word(w):
			push_error("TC12: '%s' is in dictionary — invalidates this test case" % w)
			return false
	var core = GameCore.new(300)
	_zero_premiums(core)
	core.board[0][0] = "Z"
	core.board[1][0] = "Q"
	core.board[2][0] = "X"
	core.board_modifiers[0][0] = GameCore.MOD_2X
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	if score != 0:
		push_error("TC12: expected 0 for invalid ZQX, got %d" % score)
		return false
	return true

# TC13 - Modifier doubles in both directions when the tile is in a cross.
func test_modifier_doubles_in_cross() -> bool:
	var core = GameCore.new(400)
	_zero_premiums(core)
	# Cross of two valid words sharing A at (2,2) with MOD_2X:
	#   A(2,2)* T(3,2)  — horizontal "AT"
	#   A(2,2)* S(2,3)  — vertical   "AS"
	core.board[2][2] = "A"
	core.board[3][2] = "T"
	core.board[2][3] = "S"
	core.board_modifiers[2][2] = GameCore.MOD_2X
	for w in ["AT", "AS"]:
		if not GameCore.is_valid_word(w):
			push_error("TC13: '%s' not in dictionary — invalidates this test case" % w)
			return false

	var score = core._calculate_turn_score([Vector2i(2, 2)])
	# A is doubled in BOTH words:
	#   "AT" = (1*2 + 1)*2 = 6
	#   "AS" = (1*2 + 1)*2 = 6
	# total = 12
	if score != 12:
		push_error("TC13: expected 12 for cross with A=MOD_2X, got %d" % score)
		return false
	return true

# TC14 - Modifier survives lock and round transitions; clears with clear_board.
func test_modifier_survives_lock_and_clears() -> bool:
	var core = GameCore.new(500)
	var tile_dict := {"letter": "A", "modifier": GameCore.MOD_2X}
	var placed := core.place_pending_tile(tile_dict, Vector2i(0, 0))
	if not placed:
		push_error("TC14: place_pending_tile failed")
		return false
	if core.board_modifiers[0][0] != GameCore.MOD_2X:
		push_error("TC14: board_modifiers[0][0] should be MOD_2X after placement, got '%s'" %
			core.board_modifiers[0][0])
		return false
	core.clear_board()
	for x in GameCore.BOARD_SIZE:
		for y in GameCore.BOARD_SIZE:
			if core.board_modifiers[x][y] != GameCore.MOD_NONE:
				push_error("TC14: board_modifiers[%d][%d] not MOD_NONE after clear_board()" % [x, y])
				return false
	return true

# TC15 - Premium TL doubles then triples the letter, matching the sim's DL/TL math.
func test_premium_tl_letter_math() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_premiums[0][0] = GameCore.PREM_TL
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (1+1)*2 = 4
	# CAT = (3*3 + 1 + 1)*2 = 22
	# total = 26
	if score != 26:
		push_error("TC15: expected 26 for CAT with C=PREM_TL, got %d" % score)
		return false
	return true

# TC16 - Premium TW triples every word sharing the cell (word bonus applies after sum).
func test_premium_tw_word_math() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_premiums[1][0] = GameCore.PREM_TW
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (1+1)*2*3 = 12
	# CAT = (3+1+1)*2*3 = 30
	# total = 42
	if score != 42:
		push_error("TC16: expected 42 for CAT with A=PREM_TW, got %d" % score)
		return false
	return true

# TC17 - Tile MOD_2X and cell PREM_DL stack: tile mod applies before the letter premium.
func test_premium_stacking_mod_and_dl() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[0][0] = GameCore.MOD_2X
	core.board_premiums[0][0] = GameCore.PREM_DL
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# C = 3*2*2 = 12
	# AT  = (1+1)*2 = 4
	# CAT = (12+1+1)*2 = 28
	# total = 32
	if score != 32:
		push_error("TC17: expected 32 for CAT with C=MOD_2X+PREM_DL, got %d" % score)
		return false
	return true

# TC18 - Premium reroll is seed-deterministic; exactly 8 of 64 cells are non-PREM_NONE.
func test_premium_reroll_determinism() -> bool:
	var core_a = GameCore.new(42)
	var core_b = GameCore.new(42)
	var non_none_count := 0
	for x in GameCore.BOARD_SIZE:
		for y in GameCore.BOARD_SIZE:
			if core_a.board_premiums[x][y] != core_b.board_premiums[x][y]:
				push_error("TC18: premium layouts diverged at (%d,%d) for same seed" % [x, y])
				return false
			if core_a.board_premiums[x][y] != GameCore.PREM_NONE:
				non_none_count += 1
	if non_none_count != 8:
		push_error("TC18: expected 8 non-PREM_NONE cells, got %d" % non_none_count)
		return false
	return true

# TC19 - Premiums persist through tile placement; clear_board() rerolls to match a same-seed twin.
func test_premium_persistence_and_reroll() -> bool:
	var core = GameCore.new(1000)
	var twin = GameCore.new(1000)
	var prem_pos := Vector2i(-1, -1)
	for x in GameCore.BOARD_SIZE:
		for y in GameCore.BOARD_SIZE:
			if core.board_premiums[x][y] != GameCore.PREM_NONE:
				prem_pos = Vector2i(x, y)
	if prem_pos.x < 0:
		push_error("TC19: no premium cell found")
		return false
	var before: String = core.board_premiums[prem_pos.x][prem_pos.y]
	core.place_pending_tile({"letter": "A", "modifier": GameCore.MOD_NONE}, prem_pos)
	if core.board_premiums[prem_pos.x][prem_pos.y] != before:
		push_error("TC19: placing a tile mutated board_premiums")
		return false

	core.clear_board()
	twin.clear_board()
	for x in GameCore.BOARD_SIZE:
		for y in GameCore.BOARD_SIZE:
			if core.board[x][y] != "" or core.board_modifiers[x][y] != GameCore.MOD_NONE:
				push_error("TC19: clear_board left stale letter/modifier at (%d,%d)" % [x, y])
				return false
			if core.board_premiums[x][y] != twin.board_premiums[x][y]:
				push_error("TC19: post-clear premium layout diverged from same-seed twin at (%d,%d)" % [x, y])
				return false
	return true

# TC20 - Word multiplier doubles the whole run it touches, not others.
func test_word_mult_doubles_run() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[0][0] = GameCore.MOD_WORD_2X
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (1+1)*2 = 4                      (C's word-mult isn't in AT's run)
	# CAT = (3+1+1)*2*2 = 20
	# total = 24
	if score != 24:
		push_error("TC20: expected 24 for CAT with C=MOD_WORD_2X, got %d" % score)
		return false
	return true

# TC21 - Two word-mult tiles in one run multiply (x2 * x2 = x4).
func test_word_mult_stacks_multiplicatively() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[0][0] = GameCore.MOD_WORD_2X
	core.board_modifiers[2][0] = GameCore.MOD_WORD_2X
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (1+1)*2*2 = 8     (T's word-mult is in AT's run)
	# CAT = (3+1+1)*2*2*2 = 40
	# total = 48
	if score != 48:
		push_error("TC21: expected 48 for CAT with C,T=MOD_WORD_2X, got %d" % score)
		return false
	return true

# TC22 - A MOD_WILD tile scores 0 for its slot but the word still validates/scores.
func test_wildcard_scores_zero_for_slot() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[1][0] = GameCore.MOD_WILD
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (0+1)*2 = 2   (A is the wild, worth 0)
	# CAT = (3+0+1)*2 = 8
	# total = 10  (vs. 14 with a real A)
	if score != 10:
		push_error("TC22: expected 10 for CAT with wild A, got %d" % score)
		return false
	return true

# TC23 - A word-mult tile and a PREM_DW cell multiply into the same accumulator.
func test_word_mult_stacks_with_premium_dw() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[1][0] = "A"
	core.board[2][0] = "T"
	core.board_modifiers[0][0] = GameCore.MOD_WORD_2X
	core.board_premiums[1][0] = GameCore.PREM_DW
	var score = core._calculate_turn_score([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	# AT  = (1+1) * 2(bonus) * 2(DW on A) = 8      (C's word-mult isn't in AT's run)
	# CAT = (3+1+1) * 2(bonus) * 2(DW) * 2(word-mult) = 5 * 8 = 40
	# total = 48
	if score != 48:
		push_error("TC23: expected 48 for CAT with C=MOD_WORD_2X + A=PREM_DW, got %d" % score)
		return false
	return true

# TC24 - _resolve_wildcards picks the score-maximizing letter, alphabetical on
# ties, deterministically.
func test_resolve_wildcards_maximizes() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[2][0] = "T"
	core.board_modifiers[1][0] = GameCore.MOD_WILD
	core._resolve_wildcards()
	if core.board[1][0] != "A":
		push_error("TC24: expected wild between C/T to resolve to 'A', got '%s'" % core.board[1][0])
		return false

	var core_b = GameCore.new(123)
	_zero_premiums(core_b)
	core_b.board[0][0] = "C"
	core_b.board[2][0] = "T"
	core_b.board_modifiers[1][0] = GameCore.MOD_WILD
	core_b._resolve_wildcards()
	if core_b.board[1][0] != core.board[1][0]:
		push_error("TC24: resolution not stable across two identical cores")
		return false

	var core_c = GameCore.new(123)
	_zero_premiums(core_c)
	core_c.board_modifiers[4][4] = GameCore.MOD_WILD
	core_c._resolve_wildcards()
	if core_c.board[4][4] != "A":
		push_error("TC24: isolated wild (all letters score 0) should resolve to 'A', got '%s'" % core_c.board[4][4])
		return false

	return true

# TC25 - A resolved wildcard is frozen: later turns never re-optimise it, even
# when the growing board would make a different letter strictly better. Mirrors
# the live lock (a locked blank has current_tile == null and is skipped).
func test_resolved_wildcard_is_frozen() -> bool:
	var core = GameCore.new(123)
	_zero_premiums(core)
	core.board[0][0] = "C"
	core.board[2][0] = "T"
	core.board_modifiers[1][0] = GameCore.MOD_WILD
	core._resolve_wildcards()
	if core.board[1][0] != "A":
		push_error("TC25: first wild should resolve to 'A' (CAT), got '%s'" % core.board[1][0])
		return false

	# Grow the board so column x=1 becomes "?AX": _AX words (FAX/TAX/WAX...) score
	# 36 there versus ~30 for 'A', so an unfrozen wild WOULD move off 'A'.
	core.board[1][1] = "A"
	core.board[1][2] = "X"
	# A second, unplayed wild that must still resolve.
	core.board[3][4] = "C"
	core.board[5][4] = "T"
	core.board_modifiers[4][4] = GameCore.MOD_WILD

	core._resolve_wildcards()

	if core.board[1][0] != "A":
		push_error("TC25: frozen wild was re-resolved to '%s' — should stay 'A'" % core.board[1][0])
		return false
	if core.board[4][4] != "A":
		push_error("TC25: new wild should resolve to 'A' (CAT), got '%s'" % core.board[4][4])
		return false
	return true

# TSM7 - Empty build yields zero MOD_2X tiles across N refills.
func test_empty_build_no_modifiers() -> bool:
	var core = GameCore.new(600, {})
	# Check initial rack has no modifiers
	for t in core.rack:
		if t.modifier != GameCore.MOD_NONE:
			push_error("TSM7: empty build should have no modifiers in initial rack")
			return false
	# Simulate 50 refills; none should carry MOD_2X
	for _refill_count in 50:
		core.rack.clear()
		core.refill_rack()
		for t in core.rack:
			if t.modifier == GameCore.MOD_2X:
				push_error("TSM7: empty build should never add MOD_2X, but found one")
				return false
	return true

# TSM8 - {MOD_2X: 2} guarantees exactly 2 MOD_2X tiles on distinct rack indices.
func test_build_guarantees_2x_count() -> bool:
	var core = GameCore.new(700, {GameCore.MOD_2X: 2})
	# Initial rack refill
	var mod2x_indices: Array = []
	for i in core.rack.size():
		if core.rack[i].modifier == GameCore.MOD_2X:
			mod2x_indices.append(i)
	if mod2x_indices.size() != 2:
		push_error("TSM8 initial: expected 2 MOD_2X tiles, got %d" % mod2x_indices.size())
		return false
	if mod2x_indices[0] == mod2x_indices[1]:
		push_error("TSM8: MOD_2X tiles on same index")
		return false
	# Multiple refills should maintain the guarantee
	for _refill_count in 20:
		core.rack.clear()
		core.refill_rack()
		var count := 0
		for t in core.rack:
			if t.modifier == GameCore.MOD_2X:
				count += 1
		if count != 2:
			push_error("TSM8 refill %d: expected 2 MOD_2X, got %d" % [_refill_count, count])
			return false
	return true

# TSM9 - Over-stack {MOD_2X: 99} gracefully tops out; no crash, no infinite loop.
func test_build_over_stack_graceful() -> bool:
	var core = GameCore.new(800, {GameCore.MOD_2X: 99})
	# RACK_SIZE = 7, all tiles start unmodified, so we can add at most 7 MOD_2X.
	# Even though the build requests 99, we expect exactly 7 MOD_2X tiles.
	var expected_mod_count := GameCore.RACK_SIZE
	var actual_count := 0
	for t in core.rack:
		if t.modifier == GameCore.MOD_2X:
			actual_count += 1
	if actual_count != expected_mod_count:
		push_error("TSM9: expected %d MOD_2X (limited by rack size), got %d" % [expected_mod_count, actual_count])
		return false
	# No crash or infinite loop if we refill several times
	for _i in 10:
		core.rack.clear()
		core.refill_rack()
	return true

# TSM10 - Upgrade auto-pick populates letter_modifiers at intervals (rounds 4, 7, ...).
func test_upgrade_auto_pick_at_intervals() -> bool:
	var core = GameCore.new(999)

	# Manually step through game, forcing round wins.
	while core.current_round <= 7 and not core.is_game_over:
		core.round_score = core.target_score
		var placed: Array = []
		core.end_turn(placed)

	# Should have auto-picked at rounds 4 and 7, so letter_modifiers should have 2 entries.
	var lmod_count: int = core.letter_modifiers.size()
	if lmod_count < 1:
		push_error("TSM10: expected letter_modifiers to have entries after rounds 4 and 7, got %d" % lmod_count)
		return false
	# Each auto-picked value should be a letter-bound modifier (never MOD_WILD,
	# which lives in modifier_build instead).
	for letter in core.letter_modifiers:
		var v: String = core.letter_modifiers[letter]
		if v != GameCore.MOD_2X and v != GameCore.MOD_3X and v != GameCore.MOD_WORD_2X and v != GameCore.MOD_WORD_3X:
			push_error("TSM10: expected letter_modifiers[%s] to be a letter-bound modifier, got '%s'" % [letter, v])
			return false

	return true

# TSM11 - Upgrade offers: distinct, unowned letters; deterministic with fixed seed
func test_upgrade_offers_distinct_unowned_deterministic() -> bool:
	# Test A: offers contain no already-owned letters and are distinct
	var core = GameCore.new(12345)
	core.letter_modifiers["A"] = GameCore.MOD_2X
	core.letter_modifiers["E"] = GameCore.MOD_3X
	var offers = core._generate_upgrade_offers()

	if offers.size() > GameCore.UPGRADE_OFFER_COUNT:
		push_error("TSM11A: expected at most %d offers, got %d" % [GameCore.UPGRADE_OFFER_COUNT, offers.size()])
		return false

	var seen: Array[String] = []
	for offer in offers:
		var letter: String = offer["letter"]
		# Check it's not already owned
		if core.letter_modifiers.has(letter):
			push_error("TSM11A: offer letter '%s' is already owned" % letter)
			return false
		# Check it's distinct
		if letter in seen:
			push_error("TSM11A: offer letter '%s' appears twice" % letter)
			return false
		seen.append(letter)

	# Test B: same seed produces same offers (determinism)
	var core_a = GameCore.new(54321)
	var offers_a = core_a._generate_upgrade_offers()
	var core_b = GameCore.new(54321)
	var offers_b = core_b._generate_upgrade_offers()

	if offers_a.size() != offers_b.size():
		push_error("TSM11B: same seed produced different offer counts: %d vs %d" % [offers_a.size(), offers_b.size()])
		return false

	for i in offers_a.size():
		var oa: Dictionary = offers_a[i]
		var ob: Dictionary = offers_b[i]
		if oa["letter"] != ob["letter"] or oa["modifier"] != ob["modifier"]:
			push_error("TSM11B: same seed produced different offers at index %d" % i)
			return false

	return true

# TC26 - A blank is a fallback, not a substitute: place_pending spends a real tile
# when the rack has the letter and only reaches for the wild when it does not.
# Regression — skipping wilds outright left no route to ever place one.
func test_wild_is_placement_fallback_not_substitute() -> bool:
	var core = GameCore.new(900)
	core.rack = [
		{"letter": "E", "modifier": GameCore.MOD_NONE},
		{"letter": "Q", "modifier": GameCore.MOD_WILD},
	]
	if not core.place_pending("E", Vector2i(0, 0)):
		push_error("TC26: place_pending('E') failed with a real E in the rack")
		return false
	if core.board_modifiers[0][0] != GameCore.MOD_NONE:
		push_error("TC26: spent the wildcard while a real E was available")
		return false
	if not core.place_pending("Z", Vector2i(2, 2)):
		push_error("TC26: place_pending('Z') failed — the wildcard should cover it")
		return false
	if core.board_modifiers[2][2] != GameCore.MOD_WILD:
		push_error("TC26: expected the wildcard on (2,2), got '%s'" % core.board_modifiers[2][2])
		return false
	if not core.rack.is_empty():
		push_error("TC26: expected an empty rack, got %d tiles" % core.rack.size())
		return false
	return true

# TC27 - A wildcard is never spent on a discard.
func test_wild_is_not_discardable() -> bool:
	var core = GameCore.new(901)
	core.rack = [{"letter": "E", "modifier": GameCore.MOD_WILD}]
	var before: int = core.discards_left
	if core.discard_tile("E"):
		push_error("TC27: discarded a wildcard")
		return false
	if core.discards_left != before:
		push_error("TC27: discard budget spent on a rejected wildcard discard")
		return false
	return true

# TSM12 - {MOD_WILD: 2} guarantees exactly 2 wild tiles in the rack, including
# after a later refill.
func test_wild_build_guarantees_count() -> bool:
	var core = GameCore.new(700, {GameCore.MOD_WILD: 2})
	var count := 0
	for t in core.rack:
		if t.modifier == GameCore.MOD_WILD:
			count += 1
	if count != 2:
		push_error("TSM12 initial: expected 2 MOD_WILD tiles, got %d" % count)
		return false
	core.rack.clear()
	core.refill_rack()
	count = 0
	for t in core.rack:
		if t.modifier == GameCore.MOD_WILD:
			count += 1
	if count != 2:
		push_error("TSM12 refill: expected 2 MOD_WILD tiles, got %d" % count)
		return false
	return true

# TSM13 - A MOD_WILD offer routed through the auto-pick increments
# modifier_build, leaving letter_modifiers untouched.
func test_wild_offer_routes_to_build() -> bool:
	var core = GameCore.new(1)
	var offer := {"letter": "?", "modifier": GameCore.MOD_WILD}
	core._apply_upgrade_offer(offer)
	if core.modifier_build.get(GameCore.MOD_WILD, 0) != 1:
		push_error("TSM13: expected modifier_build[MOD_WILD] == 1, got %s" % str(core.modifier_build))
		return false
	if core.letter_modifiers.size() != 0:
		push_error("TSM13: letter_modifiers should be untouched, got %s" % str(core.letter_modifiers))
		return false
	return true

# Test discard excludes same letter on replacement draw
func test_discard_excludes_same_letter() -> bool:
	var core = GameCore.new(123)
	var before: String = core.rack[0]["letter"]
	if not core.discard_tile(before):
		push_error("test_discard_excludes: discard failed"); return false
	# the replacement at the same slot must not be the discarded letter
	if core.rack[0]["letter"] == before:
		push_error("test_discard_excludes: redrew the same letter"); return false
	return true

# Test discard budget resets each round
func test_discard_budget_resets_each_round() -> bool:
	var core = GameCore.new(7)
	core.discards_left = 0
	# force a round advance
	core.round_score = core.target_score
	core.end_turn([])
	if core.discards_left != GameCore.DISCARDS_PER_ROUND:
		push_error("test_discard_reset: expected %d, got %d" % [GameCore.DISCARDS_PER_ROUND, core.discards_left]); return false
	return true

# Test discard is deterministic under seed
func test_discard_deterministic_under_seed() -> bool:
	var a = GameCore.new(999)
	var b = GameCore.new(999)
	var la: String = a.rack[0]["letter"]
	a.discard_tile(la)
	b.discard_tile(b.rack[0]["letter"])
	if a.rack[0]["letter"] != b.rack[0]["letter"]:
		push_error("test_discard_determinism: same seed diverged"); return false
	return true
