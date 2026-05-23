class_name DiagonalClusterStrategy
extends "res://scripts/sim/strategy.gd"

# Diagonal-sweep strategy. Fills the board in this order:
#   sweep 0 (main): (0,0), (1,1), (2,2), ..., (7,7)
#   sweep +1:      (0,1), (1,2), ..., (6,7)
#   sweep -1:      (1,0), (2,1), ..., (7,6)
#   sweep +2:      (0,2), ..., (5,7)
#   sweep -2:      (2,0), ..., (7,5)
#   ... and so on.
# Each sweep places tiles whose orthogonal neighbors are tiles from the
# prior sweep, so every new tile typically forms two >=2-letter cross-words
# (one horizontal, one vertical) — which the scorer extracts.
# Stateless: derives the next cells to fill from the current board snapshot.

func pick_moves(core) -> Array:
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

func _get_letter_points(letter: String) -> int:
	var points_map := {
		"Q": 10, "Z": 10, "X": 8, "J": 8, "K": 5, "F": 4, "H": 4, "V": 4, "W": 4, "Y": 4,
		"B": 3, "C": 3, "M": 3, "P": 3, "D": 2, "G": 2, "L": 1, "N": 1, "R": 1, "S": 1,
		"T": 1, "U": 1, "E": 1, "A": 1, "I": 1, "O": 1
	}
	return points_map.get(letter.to_upper(), 1)

func get_name() -> String:
	return "diagonal_cluster"
