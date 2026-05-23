class_name WordSearchStrategy
extends "res://scripts/sim/strategy.gd"

# Word search strategy: tries to form valid dictionary words, respecting 50ms time budget.

const GameCore = preload("res://scripts/sim/game_core.gd")
const TIME_BUDGET_MS = 50

func pick_moves(core) -> Array:
	var start_ms = Time.get_ticks_msec()
	var candidates = []

	# Pick an anchor cell
	var anchor = _pick_anchor_cell(core)
	if anchor == Vector2i(-1, -1):
		# Board is full or can't find anchor, random fallback
		return _random_fallback(core)

	# Try to find words in both directions
	for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
		if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
			break

		var words = _find_words_in_direction(core, anchor, direction, start_ms)
		for word_moves in words:
			if word_moves.size() > 0:
				candidates.append(word_moves)

	# Return the best candidate
	if candidates.size() > 0:
		# Score each candidate and pick the best
		var best = candidates[0]
		var best_score = _score_moves(core, best)

		for i in range(1, candidates.size()):
			var score = _score_moves(core, candidates[i])
			if score > best_score:
				best_score = score
				best = candidates[i]

		return best

	# No valid word found, random fallback
	return _random_fallback(core)

func _pick_anchor_cell(core) -> Vector2i:
	# Find cells adjacent to existing letters
	var adjacent = []
	for x in core.BOARD_SIZE:
		for y in core.BOARD_SIZE:
			var pos = Vector2i(x, y)
			if not core.is_cell_empty(pos):
				continue
			# Check if adjacent
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var adj_pos = pos + dir
				if adj_pos.x >= 0 and adj_pos.x < core.BOARD_SIZE and adj_pos.y >= 0 and adj_pos.y < core.BOARD_SIZE:
					if core.board[adj_pos.x][adj_pos.y] != "":
						adjacent.append(pos)
						break

	if adjacent.size() > 0:
		return adjacent[core.rng.randi() % adjacent.size()]

	# Board is empty, use center
	var center = Vector2i(core.BOARD_SIZE / 2, core.BOARD_SIZE / 2)
	if core.is_cell_empty(center):
		return center

	return Vector2i(-1, -1)

func _find_words_in_direction(core, anchor: Vector2i, direction: Vector2i, start_ms: int) -> Array:
	var words = []
	var rack_ltrs = core.rack_letters()

	for subset_size in range(1, min(core.tiles_per_turn + 1, rack_ltrs.size() + 1)):
		if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
			break

		# Try all permutations of this size
		var subsets = _get_rack_subsets(rack_ltrs, subset_size)
		for subset in subsets:
			if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
				break

			# Try placing this subset at the anchor
			var word_text = _try_form_word(core, anchor, direction, subset)
			if not word_text.is_empty() and _is_valid_word(word_text):
				# Valid word! Convert to moves
				var moves = _subset_to_moves(core, anchor, direction, subset, word_text)
				if moves.size() > 0:
					words.append(moves)

	return words

func _try_form_word(core, anchor: Vector2i, direction: Vector2i, letters: Array) -> String:
	# Try to form a word starting at anchor, using letters in order
	var text = ""
	var pos = anchor
	var letter_idx = 0

	while letter_idx < letters.size():
		if pos.x < 0 or pos.x >= core.BOARD_SIZE or pos.y < 0 or pos.y >= core.BOARD_SIZE:
			return ""

		if not core.is_cell_empty(pos):
			# Skip occupied cells
			text += core.board[pos.x][pos.y]
		else:
			if letter_idx < letters.size():
				text += letters[letter_idx]
				letter_idx += 1

		pos += direction

	return text

func _subset_to_moves(core, anchor: Vector2i, direction: Vector2i, letters: Array, word_text: String) -> Array:
	var moves = []
	var pos = anchor
	var letter_idx = 0

	for ch in word_text:
		if pos.x < 0 or pos.x >= core.BOARD_SIZE or pos.y < 0 or pos.y >= core.BOARD_SIZE:
			break

		if core.is_cell_empty(pos):
			if letter_idx < letters.size() and ch == letters[letter_idx]:
				moves.append({"letter": ch, "pos": pos})
				letter_idx += 1

		pos += direction

	return moves

func _get_rack_subsets(rack_ltrs: Array, size: int) -> Array:
	# Simple implementation: just unique combinations
	var subsets = []
	var letters_available = {}
	for letter in rack_ltrs:
		letters_available[letter] = letters_available.get(letter, 0) + 1

	# Generate subsets by picking different letters
	var current = []
	_generate_subsets(letters_available, size, current, subsets)
	return subsets

func _generate_subsets(available: Dictionary, needed: int, current: Array, result: Array) -> void:
	if needed == 0:
		if current.size() > 0:
			result.append(current.duplicate())
		return

	for letter in available.keys():
		if available[letter] > 0:
			available[letter] -= 1
			current.append(letter)
			_generate_subsets(available, needed - 1, current, result)
			current.pop_back()
			available[letter] += 1

func _score_moves(core, moves: Array) -> int:
	if moves.is_empty():
		return 0

	var score = 0
	for move in moves:
		score += _get_letter_points(move.letter)

	return score

func _get_letter_points(letter: String) -> int:
	# Fallback scoring based on Scrabble values
	var points_map = {
		"Q": 10, "Z": 10, "X": 8, "J": 8, "K": 5, "F": 4, "H": 4, "V": 4, "W": 4, "Y": 4,
		"B": 3, "C": 3, "M": 3, "P": 3, "D": 2, "G": 2, "L": 1, "N": 1, "R": 1, "S": 1,
		"T": 1, "U": 1, "E": 1, "A": 1, "I": 1, "O": 1
	}
	return points_map.get(letter.to_upper(), 1)

func _is_valid_word(word: String) -> bool:
	if word.length() < 2:
		return false
	return GameCore.is_valid_word(word)

func _random_fallback(core) -> Array:
	# Place one random tile
	var rack_ltrs = core.rack_letters()
	if rack_ltrs.is_empty():
		return []

	var letter = rack_ltrs[core.rng.randi() % rack_ltrs.size()]
	var pos = Vector2i(core.rng.randi() % core.BOARD_SIZE, core.rng.randi() % core.BOARD_SIZE)

	for _attempt in 100:
		if core.is_cell_empty(pos):
			return [{"letter": letter, "pos": pos}]
		pos = Vector2i(core.rng.randi() % core.BOARD_SIZE, core.rng.randi() % core.BOARD_SIZE)

	return []

func get_name() -> String:
	return "word_search"
