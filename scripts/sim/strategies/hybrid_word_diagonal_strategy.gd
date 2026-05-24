class_name HybridWordDiagonalStrategy
extends "res://scripts/sim/strategy.gd"

# Hybrid strategy: tries to form valid words first, then falls back to diagonal clustering.
# If a valid word can be formed, place it. Otherwise, use diagonal sweep for tile placement.

const GameCore = preload("res://scripts/sim/game_core.gd")
const TIME_BUDGET_MS = 50

func pick_moves(core) -> Array:
	var start_ms = Time.get_ticks_msec()

	# First, try word search approach
	var word_moves = _try_word_search(core, start_ms)
	if word_moves.size() > 0:
		return word_moves

	# If no word found, fall back to diagonal clustering
	return _try_diagonal_cluster(core)

func _try_word_search(core, start_ms: int) -> Array:
	var candidates = []

	# Pick an anchor cell
	var anchor = _pick_anchor_cell(core)
	if anchor == Vector2i(-1, -1):
		return []

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
		var best = candidates[0]
		var best_score = _score_moves(core, best)

		for i in range(1, candidates.size()):
			var score = _score_moves(core, candidates[i])
			if score > best_score:
				best_score = score
				best = candidates[i]

		return best

	return []

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

func _try_diagonal_cluster(core) -> Array:
	var moves: Array = []
	var local: Array = _copy_board(core)
	var rack_copy: Array = core.rack_letters().duplicate()
	var tiles: int = min(int(core.tiles_per_turn), rack_copy.size())
	var order: Array = _diagonal_sweep_order(core.BOARD_SIZE)

	for pos in order:
		if moves.size() >= tiles:
			break
		if local[pos.x][pos.y] != "":
			continue
		var letter: String = _pick_letter(rack_copy)
		if letter == "":
			break
		moves.append({"letter": letter, "pos": pos})
		local[pos.x][pos.y] = letter
		rack_copy.erase(letter)

	return moves

func _diagonal_sweep_order(size: int) -> Array:
	# Build [0, +1, -1, +2, -2, ..., +(size-1), -(size-1)] as the offset
	# sequence (y - x), then walk each diagonal from low x to high x.
	var offsets: Array = [0]
	for k in range(1, size):
		offsets.append(k)
		offsets.append(-k)

	var out: Array = []
	for offset in offsets:
		for x in size:
			var y: int = x + offset
			if y >= 0 and y < size:
				out.append(Vector2i(x, y))
	return out

func _copy_board(core) -> Array:
	var out: Array = []
	out.resize(core.BOARD_SIZE)
	for x in core.BOARD_SIZE:
		out[x] = []
		out[x].resize(core.BOARD_SIZE)
		for y in core.BOARD_SIZE:
			out[x][y] = core.board[x][y]
	return out

func _pick_letter(rack: Array) -> String:
	if rack.is_empty():
		return ""
	var best: String = rack[0]
	var best_pts: int = _get_letter_points(best)
	for letter in rack:
		var p: int = _get_letter_points(letter)
		if p > best_pts:
			best_pts = p
			best = letter
	return best

func get_name() -> String:
	return "hybrid_word_diagonal"
