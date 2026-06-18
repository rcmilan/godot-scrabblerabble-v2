# res://scripts/navigation.gd
class_name Navigation
extends RefCounted

enum Region { BOARD, RACK }

const BOARD_SIZE: int = 8

var region:     int      = Region.BOARD    # where keyboard input currently goes
var board_pos:  Vector2i = Vector2i(3, 3)  # persistent board anchor
var rack_index: int      = 0

# Single transition function. dir is a unit Vector2i: (-1,0)/(1,0)/(0,-1)/(0,1).
# rack_size is passed in because the rack is dynamic.
func move(dir: Vector2i, rack_size: int) -> void:
	if region == Region.BOARD:
		if dir == Vector2i(0, 1) and board_pos.y >= BOARD_SIZE - 1:
			region = Region.RACK
			rack_index = clampi(board_pos.x, 0, max(0, rack_size - 1))
		else:
			board_pos.x = clampi(board_pos.x + dir.x, 0, BOARD_SIZE - 1)
			board_pos.y = clampi(board_pos.y + dir.y, 0, BOARD_SIZE - 1)
	else: # Region.RACK
		if dir == Vector2i(0, -1):
			region = Region.BOARD                # board_pos retained as the anchor
		elif dir.y == 0:
			rack_index = clampi(rack_index + dir.x, 0, max(0, rack_size - 1))
		# dir down in the rack is a deliberate no-op.

# Feed the model from mouse click / focus. Single writer, many triggers.
func set_board(pos: Vector2i) -> void:
	region = Region.BOARD
	board_pos = pos

func set_rack(idx: int) -> void:
	region = Region.RACK
	rack_index = idx
