# res://scripts/main.gd
extends Control

const TILES_PER_TURN: int = 4   # quantas peças o jogador deve colocar antes de pontuar
const WORD_BONUS_MULTIPLIER: int = 2  # bônus aplicado por palavra válida

@onready var board: Board = $VBoxContainer/Board
@onready var rack: Rack = $VBoxContainer/Rack
@onready var score_label: Label = $VBoxContainer/HUD/ScoreLabel
@onready var tiles_left_label: Label = $VBoxContainer/HUD/TilesLeftLabel
@onready var end_turn_button: Button = $VBoxContainer/HUD/EndTurnButton

var total_score: int = 0
var pending_cells: Array[BoardCell] = []   # células com peças colocadas neste turno
var cursor: Vector2i = Vector2i(0, 0)

func _ready() -> void:
	add_to_group("main")
	randomize()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	# Foco inicial na célula central.
	cursor = Vector2i(3, 3)
	board.focus_cell(cursor)
	board.cell_focused.connect(_on_cell_focused)
	_update_hud()

func _on_cell_focused(cell: BoardCell) -> void:
	cursor = cell.grid_pos

# ---------- Input: teclado ----------
func _unhandled_input(event: InputEvent) -> void:
	# Move cursor com setas (usa as ações padrão ui_left/right/up/down).
	if event.is_action_pressed("ui_left"):
		_move_cursor(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_cursor(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_cursor(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(Vector2i(0, 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm_turn"):
		_on_end_turn_pressed()
	# Letra A-Z para colocar uma peça do rack na célula atual.
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode >= KEY_A and key_event.keycode <= KEY_Z:
			var letter := char(key_event.keycode)  # 'A'..'Z'
			_try_place_letter_on_cursor(letter)

func _move_cursor(delta: Vector2i) -> void:
	var new_pos := cursor + delta
	new_pos.x = clamp(new_pos.x, 0, Board.BOARD_SIZE - 1)
	new_pos.y = clamp(new_pos.y, 0, Board.BOARD_SIZE - 1)
	cursor = new_pos
	board.focus_cell(cursor)

func _try_place_letter_on_cursor(letter: String) -> void:
	var cell := board.get_cell(cursor)
	if cell == null or not cell.is_empty():
		return
	var tile := rack.find_tile_with_letter(letter)
	if tile == null:
		return
	_place_tile_on_cell(tile, cell)

# ---------- Drag and drop callbacks (chamados por BoardCell e Rack) ----------
func on_tile_dropped_on_cell(tile: Tile, cell: BoardCell) -> void:
	if not cell.is_empty():
		return
	_place_tile_on_cell(tile, cell)

func on_tile_returned_to_rack(tile: Tile) -> void:
	var prev_cell := board.get_cell(tile.board_pos)
	if prev_cell:
		prev_cell.clear_pending()
		pending_cells.erase(prev_cell)
	tile.location = "rack"
	tile.board_pos = Vector2i(-1, -1)
	tile.visible = true
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	rack.add_child(tile)
	rack.tiles_in_hand.append(tile)
	_update_hud()
	
func _place_tile_on_cell(tile: Tile, cell: BoardCell) -> void:
	rack.remove_tile(tile)
	cell.place_tile(tile)
	# Hide the tile node: the cell's Label already shows the letter.
	# We keep the Tile alive (parented to Main, hidden) so drag/return logic
	# can still reference it until lock_pending() frees it.
	if tile.get_parent():
		tile.get_parent().remove_child(tile)
	add_child(tile)
	tile.visible = false
	pending_cells.append(cell)
	_update_hud()
	if pending_cells.size() >= TILES_PER_TURN:
		_on_end_turn_pressed()
		
# ---------- Final do turno: pontuar ----------
func _on_end_turn_pressed() -> void:
	if pending_cells.is_empty():
		return
	var turn_score := _calculate_turn_score()
	total_score += turn_score
	# "Tranca" as letras colocadas e completa o rack.
	for c in pending_cells:
		c.lock_pending()
	pending_cells.clear()
	rack.refill()
	_update_hud()

func _calculate_turn_score() -> int:
	# 1) Coleta todas as palavras formadas (horizontal + vertical) que toquem
	#    em pelo menos uma célula nova deste turno.
	var words_found: Array = []  # cada item: { "letters": [{cell, letter}], "text": String }
	var seen_lines: Dictionary = {}  # evita contar a mesma palavra duas vezes

	for cell in pending_cells:
		var horiz := _extract_word_in_direction(cell, Vector2i(1, 0))
		var vert  := _extract_word_in_direction(cell, Vector2i(0, 1))
		if horiz.text.length() >= 2 and not seen_lines.has("H_" + str(horiz.start)):
			words_found.append(horiz)
			seen_lines["H_" + str(horiz.start)] = true
		if vert.text.length() >= 2 and not seen_lines.has("V_" + str(vert.start)):
			words_found.append(vert)
			seen_lines["V_" + str(vert.start)] = true

	# 2) Soma pontos.
	var total := 0
	for w in words_found:
		var word_points := 0
		for letter in (w.text as String):
			word_points += GameData.score_for_letter(letter)
		if GameData.is_valid_word(w.text):
			word_points *= WORD_BONUS_MULTIPLIER
			print("VALID:   %s = %d points" % [w.text, word_points])
		else:
			print("invalid: %s = %d points (no bonus)" % [w.text, word_points])
		total += word_points
	return total

# Retorna { text: "ABC", start: Vector2i } percorrendo a partir de `cell`
# para trás e para frente na direção dada (1,0) ou (0,1).
func _extract_word_in_direction(cell: BoardCell, dir: Vector2i) -> Dictionary:
	# Volta até o início da sequência contígua de letras.
	var start_pos := cell.grid_pos
	while true:
		var prev := start_pos - dir
		var prev_cell := board.get_cell(prev)
		if prev_cell == null or prev_cell.get_letter() == "":
			break
		start_pos = prev
	# Avança coletando letras.
	var text := ""
	var p := start_pos
	while true:
		var c := board.get_cell(p)
		if c == null or c.get_letter() == "":
			break
		text += c.get_letter()
		p += dir
	return {"text": text, "start": start_pos}

func _update_hud() -> void:
	score_label.text = "Score: %d" % total_score
	tiles_left_label.text = "Placed this turn: %d / %d" % [pending_cells.size(), TILES_PER_TURN]
