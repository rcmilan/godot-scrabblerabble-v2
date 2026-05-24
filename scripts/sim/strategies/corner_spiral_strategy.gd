class_name CornerSpiralStrategy
extends "res://scripts/sim/strategy.gd"

# Corner-spiral strategy. Fills the board in L-shaped layers from (0,0):
#   layer 0: (0,0)
#   layer 1: (0,1), (1,1), (1,0)
#   layer 2: (0,2), (1,2), (2,2), (2,1), (2,0)
#   layer k: (0,k), (1,k), ..., (k,k), (k,k-1), ..., (k,0)
# Each new tile sits adjacent to the prior layer, so the scorer typically
# extracts a >=2-letter cross-word in both directions.
# Stateless: derives the next cells to fill from the current board snapshot.

func pick_moves(core) -> Array:
	var moves: Array = []
	var local: Array = _copy_board(core)
	var rack_copy: Array = core.rack_letters().duplicate()
	var tiles: int = min(int(core.tiles_per_turn), rack_copy.size())
	var order: Array = _spiral_order(core.BOARD_SIZE)

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

func _spiral_order(size: int) -> Array:
	var out: Array = []
	for k in size:
		# Top edge of layer k: (0,k) → (k,k)
		for x in range(0, k + 1):
			out.append(Vector2i(x, k))
		# Right edge of layer k: (k,k-1) → (k,0)
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
	return "corner_spiral"
