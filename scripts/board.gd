# res://scripts/board.gd
class_name Board
extends GridContainer

const BOARD_SIZE: int = 8
const CELL_SCENE: PackedScene = preload("res://scenes/board_cell.tscn")

signal cell_focused(cell: BoardCell)

var cells: Array = []  # 2D array indexed [x][y]

func _ready() -> void:
	columns = BOARD_SIZE
	cells.resize(BOARD_SIZE)
	for x in BOARD_SIZE:
		cells[x] = []
		cells[x].resize(BOARD_SIZE)
	# Important: GridContainer fills row-by-row, so iterate y outer, x inner.
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var cell := CELL_SCENE.instantiate() as BoardCell
			cell.grid_pos = Vector2i(x, y)
			cell.custom_minimum_size = Vector2(64, 64)
			add_child(cell)
			cell.focus_entered.connect(func(): cell_focused.emit(cell))
			cells[x][y] = cell

func get_cell(pos: Vector2i) -> BoardCell:
	if pos.x < 0 or pos.x >= BOARD_SIZE or pos.y < 0 or pos.y >= BOARD_SIZE:
		return null
	return cells[pos.x][pos.y]

func focus_cell(pos: Vector2i) -> void:
	var c := get_cell(pos)
	if c:
		c.grab_focus()
