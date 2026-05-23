class_name GreedyStrategy
extends "res://scripts/sim/strategy.gd"

# Greedy strategy: places highest-point letters adjacent to existing board letters.

func pick_moves(core) -> Array:
	var moves: Array = []
	var tiles_to_place = core.tiles_per_turn

	for _i in tiles_to_place:
		if core.rack.is_empty():
			break

		# Find all cells adjacent to existing letters (or center if board is empty)
		var candidate_cells = _find_candidate_cells(core)
		if candidate_cells.is_empty():
			# Fallback: random empty cell
			candidate_cells = _find_all_empty_cells(core)

		if candidate_cells.is_empty():
			break

		# Pick random cell from candidates
		var cell_idx = core.rng.randi() % candidate_cells.size()
		var pos = candidate_cells[cell_idx]

		# Pick highest-point letter from rack (using fallback scoring)
		var best_letter = ""
		var best_points = -1
		for letter in core.rack:
			# Use letter ASCII value as fallback (won't use GameData which isn't available in headless mode)
			var points = _get_letter_points(letter)
			if points > best_points:
				best_points = points
				best_letter = letter

		if not best_letter.is_empty():
			moves.append({"letter": best_letter, "pos": pos})

	return moves

func _get_letter_points(letter: String) -> int:
	# Fallback scoring based on Scrabble values
	var points_map = {
		"Q": 10, "Z": 10, "X": 8, "J": 8, "K": 5, "F": 4, "H": 4, "V": 4, "W": 4, "Y": 4,
		"B": 3, "C": 3, "M": 3, "P": 3, "D": 2, "G": 2, "L": 1, "N": 1, "R": 1, "S": 1,
		"T": 1, "U": 1, "E": 1, "A": 1, "I": 1, "O": 1
	}
	return points_map.get(letter.to_upper(), 1)

func _find_candidate_cells(core) -> Array:
	var candidates = []

	# Check all cells
	for x in core.BOARD_SIZE:
		for y in core.BOARD_SIZE:
			var pos = Vector2i(x, y)
			if not core.is_cell_empty(pos):
				continue

			# Check if adjacent to an existing letter
			var adjacent_directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for dir in adjacent_directions:
				var adj_pos = pos + dir
				if adj_pos.x >= 0 and adj_pos.x < core.BOARD_SIZE and adj_pos.y >= 0 and adj_pos.y < core.BOARD_SIZE:
					if core.board[adj_pos.x][adj_pos.y] != "":
						candidates.append(pos)
						break

	return candidates

func _find_all_empty_cells(core) -> Array:
	var cells = []
	for x in core.BOARD_SIZE:
		for y in core.BOARD_SIZE:
			if core.is_cell_empty(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	return cells

func get_name() -> String:
	return "greedy"
