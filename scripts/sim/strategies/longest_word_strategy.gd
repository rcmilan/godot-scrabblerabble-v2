class_name LongestWordStrategy
extends "res://scripts/sim/strategy.gd"

# Longest-word strategy: finds the longest valid word formable from the current
# rack (optionally extending existing board runs), places it, then fills
# remaining turn slots with the corner-spiral fallback.

const GameCore = preload("res://scripts/sim/game_core.gd")
const TIME_BUDGET_MS = 45

static var _dict: Dictionary = {}

static func _load_dict() -> void:
	if not _dict.is_empty():
		return
	var f := FileAccess.open("res://data/words.txt", FileAccess.READ)
	if f == null:
		push_warning("[LongestWord] could not open res://data/words.txt")
		return
	while not f.eof_reached():
		var w := f.get_line().strip_edges().to_upper()
		if w.length() >= 2 and w.length() <= 8:
			_dict[w] = true
	f.close()
	print("[LongestWord] dictionary loaded: %d words" % _dict.size())

static func _is_valid(word: String) -> bool:
	return _dict.has(word.to_upper())

func pick_moves(core) -> Array:
	_load_dict()
	var start_ms := Time.get_ticks_msec()
	var max_tiles: int = min(int(core.tiles_per_turn), core.rack_letters().size())

	# 1. Search for the best word (longest), considering board extensions first.
	var best: Dictionary = _find_best_word(core, start_ms, max_tiles)

	# 2. Convert the best word into move list.
	var moves: Array = []
	if best.word != "":
		moves = _word_to_moves(core, best)

	# 3. Fill remaining quota with corner-spiral fallback.
	if moves.size() < max_tiles:
		var local: Array = _copy_board(core)
		for m in moves:
			local[m.pos.x][m.pos.y] = m.letter

		var rack_copy: Array = core.rack_letters().duplicate()
		for m in moves:
			rack_copy.erase(m.letter)

		var order: Array = _spiral_order(core.BOARD_SIZE)
		for pos in order:
			if moves.size() >= max_tiles:
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

# ─── Word search ──────────────────────────────────────────────────────────────

# Returns {word, start, dir, new_letters_count} for the best candidate found.
func _find_best_word(core, start_ms: int, max_tiles: int) -> Dictionary:
	var best: Dictionary = {"word": "", "start": Vector2i.ZERO, "dir": Vector2i(1, 0), "new_letters_count": 0}

	# Board-extension candidates first: they reuse existing letters and can
	# produce longer words for fewer tile placements.
	for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
		if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
			break
		var runs: Array = _find_runs(core, direction)
		for run in runs:
			if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
				break
			var candidate: Dictionary = _best_extension(core, run, direction, max_tiles)
			if candidate.word.length() > best.word.length():
				best = candidate

	# Pure rack search (no existing board letters required).
	if Time.get_ticks_msec() - start_ms < TIME_BUDGET_MS:
		var rack_candidate: Dictionary = _best_rack_word(core, start_ms, max_tiles)
		if rack_candidate.word.length() > best.word.length():
			best = rack_candidate

	return best

# ─── Board-extension helpers ──────────────────────────────────────────────────

# Returns Array of {start: Vector2i, text: String} for each contiguous run.
func _find_runs(core, direction: Vector2i) -> Array:
	var runs: Array = []
	var size: int = core.BOARD_SIZE
	var perp := Vector2i(direction.y, direction.x)

	for base in size:
		var run_start := Vector2i(-1, -1)
		var run_text := ""
		for step in size:
			var pos: Vector2i
			if direction == Vector2i(1, 0):
				pos = Vector2i(step, base)
			else:
				pos = Vector2i(base, step)

			var cell: String = core.board[pos.x][pos.y]
			if cell != "":
				if run_start == Vector2i(-1, -1):
					run_start = pos
				run_text += cell
			else:
				if run_text.length() >= 1:
					runs.append({"start": run_start, "text": run_text})
				run_start = Vector2i(-1, -1)
				run_text = ""

		if run_text.length() >= 1:
			runs.append({"start": run_start, "text": run_text})

	return runs

# Tries prefix and suffix extensions of a run with rack letters.
func _best_extension(core, run: Dictionary, direction: Vector2i, max_tiles: int) -> Dictionary:
	var run_text: String = run.text
	var run_start: Vector2i = run.start
	var rack_letters: Array = core.rack_letters().duplicate()
	var size: int = core.BOARD_SIZE

	var best: Dictionary = {"word": "", "start": Vector2i.ZERO, "dir": direction, "new_letters_count": 0}

	# Maximum letters we can prepend / append is bounded by max_tiles and board space.
	var max_pre: int = min(max_tiles, _cells_before(run_start, direction, size))
	var max_suf: int = min(max_tiles, _cells_after(run_start, run_text.length(), direction, size))

	# Try all combinations of prefix length [0..max_pre] and suffix length [0..max_suf]
	# with pre + suf <= max_tiles, searching from largest total word down.
	for total_new in range(min(max_tiles, max_pre + max_suf), 0, -1):
		for pre_len in range(min(total_new, max_pre) + 1):
			var suf_len := total_new - pre_len
			if suf_len > max_suf:
				continue
			if pre_len == 0 and suf_len == 0:
				continue

			# Check if the full word length fits in the dictionary (2–8).
			var total_word_len := pre_len + run_text.length() + suf_len
			if total_word_len < 2 or total_word_len > 8:
				continue

			# Generate all permutations of (pre_len + suf_len) rack letters.
			var perms: Array = _rack_permutations(rack_letters, pre_len + suf_len)
			for perm in perms:
				var prefix: String = "".join(perm.slice(0, pre_len))
				var suffix: String = "".join(perm.slice(pre_len))
				var candidate_word: String = prefix + run_text + suffix
				if _is_valid(candidate_word):
					# Compute start position (move backwards by pre_len).
					var candidate_start: Vector2i = run_start
					for _i in pre_len:
						candidate_start -= direction
					# Verify no collision for new cells.
					if _placement_valid(core, candidate_word, candidate_start, direction, pre_len + suf_len):
						if candidate_word.length() > best.word.length():
							best = {
								"word": candidate_word,
								"start": candidate_start,
								"dir": direction,
								"new_letters_count": pre_len + suf_len
							}
							# We searched largest total_new first so this is optimal at this length.
							return best

	return best

func _cells_before(start: Vector2i, direction: Vector2i, size: int) -> int:
	if direction == Vector2i(1, 0):
		return start.x
	return start.y

func _cells_after(start: Vector2i, run_len: int, direction: Vector2i, size: int) -> int:
	if direction == Vector2i(1, 0):
		return size - (start.x + run_len)
	return size - (start.y + run_len)

# ─── Pure-rack word search ────────────────────────────────────────────────────

func _best_rack_word(core, start_ms: int, max_tiles: int) -> Dictionary:
	var rack_letters: Array = core.rack_letters().duplicate()
	var max_len: int = min(min(max_tiles, rack_letters.size()), 8)

	# Search from longest to shortest so the first hit is the best.
	for length in range(max_len, 1, -1):
		if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
			break
		var perms: Array = _rack_permutations(rack_letters, length)
		for perm in perms:
			var word: String = "".join(perm)
			if _is_valid(word):
				# Find a valid placement in spiral order.
				var placement: Dictionary = _find_spiral_placement(core, word)
				if placement.start != Vector2i(-1, -1):
					return {
						"word": word,
						"start": placement.start,
						"dir": placement.dir,
						"new_letters_count": word.length()
					}

	return {"word": "", "start": Vector2i.ZERO, "dir": Vector2i(1, 0), "new_letters_count": 0}

# Finds the earliest position in spiral order where `word` fits horizontally
# or vertically without conflicting with occupied cells.
func _find_spiral_placement(core, word: String) -> Dictionary:
	var order: Array = _spiral_order(core.BOARD_SIZE)
	for pos in order:
		for direction in [Vector2i(1, 0), Vector2i(0, 1)]:
			if _placement_valid(core, word, pos, direction, word.length()):
				return {"start": pos, "dir": direction}
	return {"start": Vector2i(-1, -1), "dir": Vector2i(1, 0)}

# Returns true if all cells for the word are either empty or already contain
# the matching letter, and the word stays within bounds.
func _placement_valid(core, word: String, start: Vector2i, direction: Vector2i, new_count: int) -> bool:
	var pos := start
	var new_placed := 0
	for i in word.length():
		if pos.x < 0 or pos.x >= core.BOARD_SIZE or pos.y < 0 or pos.y >= core.BOARD_SIZE:
			return false
		var cell: String = core.board[pos.x][pos.y]
		var ch: String = word[i]
		if cell == "":
			new_placed += 1
		elif cell != ch:
			return false
		pos += direction
	return new_placed <= new_count

# ─── Move construction ────────────────────────────────────────────────────────

func _word_to_moves(core, best: Dictionary) -> Array:
	var moves: Array = []
	var pos: Vector2i = best.start
	var rack_copy: Array = core.rack_letters().duplicate()

	for ch in best.word:
		var cell: String = core.board[pos.x][pos.y]
		if cell == "":
			# Need to place from rack.
			if rack_copy.has(ch):
				moves.append({"letter": ch, "pos": pos})
				rack_copy.erase(ch)
		# Already on board — skip.
		pos += best.dir

	return moves

# ─── Permutation helper ───────────────────────────────────────────────────────

# Generates all permutations of `length` letters drawn from `letters` (with
# repetition only if the same letter appears multiple times in `letters`).
func _rack_permutations(letters: Array, length: int) -> Array:
	var result: Array = []
	var available: Dictionary = {}
	for l in letters:
		available[l] = available.get(l, 0) + 1
	_permute(available, length, [], result)
	return result

func _permute(available: Dictionary, remaining: int, current: Array, result: Array) -> void:
	if remaining == 0:
		result.append(current.duplicate())
		return
	for letter in available.keys():
		if available[letter] > 0:
			available[letter] -= 1
			current.append(letter)
			_permute(available, remaining - 1, current, result)
			current.pop_back()
			available[letter] += 1

# ─── Spiral / fallback helpers ────────────────────────────────────────────────

func _spiral_order(size: int) -> Array:
	var out: Array = []
	for k in size:
		for x in range(0, k + 1):
			out.append(Vector2i(x, k))
		for y in range(k - 1, -1, -1):
			out.append(Vector2i(k, y))
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

func _get_letter_points(letter: String) -> int:
	var points_map := {
		"Q": 10, "Z": 10, "X": 8, "J": 8, "K": 5, "F": 4, "H": 4, "V": 4, "W": 4, "Y": 4,
		"B": 3, "C": 3, "M": 3, "P": 3, "D": 2, "G": 2, "L": 1, "N": 1, "R": 1, "S": 1,
		"T": 1, "U": 1, "E": 1, "A": 1, "I": 1, "O": 1
	}
	return points_map.get(letter.to_upper(), 1)

func get_name() -> String:
	return "longest_word"
