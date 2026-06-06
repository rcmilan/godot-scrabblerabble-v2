class_name GameCore
extends RefCounted

# Pure game logic with no Control or Node dependencies.
# This class duplicates logic from main.gd and run_state.gd.
# See ../README.md for the duplication notice.

# Progression constants (copied from RunState, main.gd, board.gd, rack.gd).
const TURNS_PER_ROUND:        int = 3
const INITIAL_TILES_PER_TURN: int = 4
const INITIAL_TARGET_SCORE:   int = 20
const WORD_BONUS_MULTIPLIER:  int = 2
const BOARD_SIZE:             int = 8
const RACK_SIZE:              int = 7
const UPGRADE_EVERY_N_ROUNDS: int = 3

const MOD_NONE: String = ""
const MOD_2X:   String = "2x"
const MOD_3X:   String = "3x"

# Letter distribution and points (from GameData, embedded here for headless mode)
const LETTER_DISTRIBUTION = {
	"A": 9, "B": 2, "C": 2, "D": 4, "E": 12, "F": 2, "G": 3,
	"H": 2, "I": 9, "J": 1, "K": 1, "L": 4, "M": 2, "N": 6,
	"O": 8, "P": 2, "Q": 1, "R": 6, "S": 4, "T": 6, "U": 4,
	"V": 2, "W": 2, "X": 1, "Y": 2, "Z": 1,
}

const LETTER_POINTS = {
	"A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2,
	"H": 4, "I": 1, "J": 8, "K": 5, "L": 1, "M": 3, "N": 1,
	"O": 1, "P": 3, "Q": 10, "R": 1, "S": 1, "T": 1, "U": 1,
	"V": 4, "W": 4, "X": 8, "Y": 4, "Z": 10,
}

# Dictionary cache shared by sim and strategies. GameData autoload isn't reliably
# available under --script, so we load data/words.txt directly. Empty on load
# failure — sim falls through to "no bonus" rather than crashing.
static var _dictionary: Dictionary = {}
static var _dictionary_loaded: bool = false

static func _ensure_dictionary_loaded() -> void:
	if _dictionary_loaded:
		return
	_dictionary_loaded = true
	var f := FileAccess.open("res://data/words.txt", FileAccess.READ)
	if f == null:
		push_warning("[GameCore] could not open res://data/words.txt — bonus disabled")
		return
	# Mirror GameData._load_dictionary filter: length 2..8 inclusive, uppercase.
	# Drifting from that filter silently changes which words trigger the 2x bonus.
	while not f.eof_reached():
		var line := f.get_line().strip_edges().to_upper()
		if line.length() >= 2 and line.length() <= 8:
			_dictionary[line] = true
	print("[GameCore] dictionary loaded: %d words" % _dictionary.size())

static func is_valid_word(text: String) -> bool:
	_ensure_dictionary_loaded()
	return _dictionary.has(text.to_upper())

# Board state: 8x8, indexed [x][y], values are letter strings.
var board: Array = []
# Parallel modifier state: same shape as board, default MOD_NONE.
var board_modifiers: Array = []

# Rack: each entry is {"letter": String, "modifier": String}.
var rack: Array = []

# RNG seeded per game.
var rng: RandomNumberGenerator

# Progression state (mirrors RunState).
var current_round:  int   = 1
var round_score:    int   = 0
var target_score:   int   = INITIAL_TARGET_SCORE
var turns_left:     int   = TURNS_PER_ROUND
var tiles_per_turn: int   = INITIAL_TILES_PER_TURN
var is_game_over:   bool  = false

# Modifier build state.
var modifier_build: Dictionary = {}
# Letter-targeted modifier state.
var letter_modifiers: Dictionary = {}

# Target curve state.
var _t_prev: float = 0.0
var _t_curr: float = float(INITIAL_TARGET_SCORE)

func _init(seed: int, build: Dictionary = {}, lmods: Dictionary = {}) -> void:
	modifier_build = build.duplicate()
	letter_modifiers = lmods.duplicate()
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	_init_board()
	refill_rack()

func _init_board() -> void:
	board.clear()
	board.resize(BOARD_SIZE)
	board_modifiers.clear()
	board_modifiers.resize(BOARD_SIZE)
	for x in BOARD_SIZE:
		board[x] = []
		board[x].resize(BOARD_SIZE)
		board_modifiers[x] = []
		board_modifiers[x].resize(BOARD_SIZE)
		for y in BOARD_SIZE:
			board[x][y] = ""
			board_modifiers[x][y] = MOD_NONE

func _draw_letter_raw() -> String:
	var bag: Array[String] = []
	for letter in LETTER_DISTRIBUTION.keys():
		for _i in LETTER_DISTRIBUTION[letter]:
			bag.append(letter)
	return bag[rng.randi() % bag.size()]

# Kept public for TC2 backward compatibility.
func draw_letter() -> String:
	return _draw_letter_raw()

func draw_tile() -> Dictionary:
	return {"letter": _draw_letter_raw(), "modifier": MOD_NONE}

func rack_letters() -> Array:
	var out: Array = []
	for t in rack:
		out.append(t.letter)
	return out

func refill_rack() -> void:
	while rack.size() < RACK_SIZE:
		rack.append(draw_tile())
	for i in range(rack.size()):
		if letter_modifiers.has(rack[i]["letter"]):
			rack[i]["modifier"] = letter_modifiers[rack[i]["letter"]]
	for mod in modifier_build.keys():
		_ensure_modifier_count_in_rack(mod, modifier_build[mod])

func _ensure_modifier_count_in_rack(mod: String, required_count: int) -> void:
	# 1. Count tiles already carrying this modifier.
	var have := 0
	for t in rack:
		if t.modifier == mod:
			have += 1
	# 2. Promote unmodified tiles until we hit required_count.
	#    Binary rule: a tile with ANY modifier is ineligible — never stack.
	while have < required_count:
		var target_idx := -1
		var target_pts := 9999
		for i in rack.size():
			var t = rack[i]
			if t.modifier != MOD_NONE:
				continue
			var pts: int = LETTER_POINTS.get(t.letter, 0)
			if pts < target_pts:
				target_pts = pts
				target_idx = i
		if target_idx < 0:
			return  # no unmodified tiles left; top out silently
		rack[target_idx].modifier = mod
		have += 1

func _generate_letter_options(count: int) -> Array[String]:
	var all_letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var options: Array[String] = []
	while options.size() < count:
		var idx := rng.randi() % 26
		var letter := all_letters[idx]
		if letter not in options:
			options.append(letter)
	return options

func is_cell_empty(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= BOARD_SIZE or pos.y < 0 or pos.y >= BOARD_SIZE:
		return false
	return board[pos.x][pos.y] == ""

# Writes tile to board only; caller is responsible for removing it from rack.
func place_pending_tile(tile: Dictionary, pos: Vector2i) -> bool:
	if not is_cell_empty(pos):
		return false
	board[pos.x][pos.y] = tile.letter
	board_modifiers[pos.x][pos.y] = tile.modifier
	return true

# Legacy wrapper: finds and removes the letter from rack, then calls place_pending_tile.
func place_pending(letter: String, pos: Vector2i) -> bool:
	for i in rack.size():
		if rack[i].letter == letter:
			var tile_dict = rack[i]
			rack.remove_at(i)
			if place_pending_tile(tile_dict, pos):
				return true
			rack.append(tile_dict)
			return false
	return false

func end_turn(pending_positions: Array) -> int:
	var turn_score := _calculate_turn_score(pending_positions)
	round_score += turn_score
	turns_left -= 1
	if round_score >= target_score:
		_advance_round()
		# Mirror the upgrade-dialog auto-pick: at each UPGRADE_EVERY_N_ROUNDS interval
		# the sim automatically adds one MOD_2X to the build, matching player behaviour.
		# Upgrades do NOT carry over — each eligible round offers exactly one pick.
		if current_round > 1 and (current_round - 1) % UPGRADE_EVERY_N_ROUNDS == 0:
			var options := _generate_letter_options(5)
			var best := options[0]
			for l in options:
				if LETTER_POINTS.get(l, 0) > LETTER_POINTS.get(best, 0):
					best = l
			var offered_mod := MOD_3X if rng.randi() % 3 == 0 else MOD_2X
			letter_modifiers[best] = offered_mod
			print("[GameCore] upgrade auto-pick — %s → %s" % [offered_mod, best])
	elif turns_left <= 0:
		is_game_over = true
	refill_rack()
	return turn_score

func _calculate_turn_score(pending_positions: Array) -> int:
	var words_found: Array = []
	var seen_lines: Dictionary = {}

	for pos in pending_positions:
		var horiz := _extract_word_in_direction(pos, Vector2i(1, 0))
		var vert := _extract_word_in_direction(pos, Vector2i(0, 1))
		if horiz.text.length() >= 2 and not seen_lines.has("H_" + str(horiz.start)):
			words_found.append(horiz)
			seen_lines["H_" + str(horiz.start)] = true
		if vert.text.length() >= 2 and not seen_lines.has("V_" + str(vert.start)):
			words_found.append(vert)
			seen_lines["V_" + str(vert.start)] = true

	var total := 0
	for w in words_found:
		if is_valid_word(w.text):
			# Full word is valid - score it with word bonus
			var word_points := _score_word_sim(w)
			total += word_points
		else:
			# Full word is invalid - try to find valid sub-words
			var sub_words_found := false
			# Try all possible sub-words (length 2+)
			for start_idx in range(w.text.length() - 1):
				for end_idx in range(start_idx + 2, w.text.length() + 1):
					var sub_word: String = w.text.substr(start_idx, end_idx - start_idx)
					if is_valid_word(sub_word):
						sub_words_found = true
						# Calculate score for sub-word
						var sub_points := 0
						for i in range(start_idx, end_idx):
							var ch: String = w.text[i]
							var cell_pos: Vector2i = w.cells[i]
							var letter_pts: int = LETTER_POINTS.get(ch.to_upper(), 0)
							var mod: String = board_modifiers[cell_pos.x][cell_pos.y]
							if mod == MOD_2X:
								letter_pts *= 2
							elif mod == MOD_3X:
								letter_pts *= 3
							sub_points += letter_pts
						# Apply word bonus if at least one new tile in sub-word
						var has_new_tile := false
						for i in range(start_idx, end_idx):
							if w.cells[i] in pending_positions:
								has_new_tile = true
								break
						if has_new_tile:
							sub_points *= WORD_BONUS_MULTIPLIER
						total += sub_points
			# If no valid sub-words, score just the letter values (no word bonus)
			if not sub_words_found:
				var letter_points := 0
				for i in (w.text as String).length():
					var ch: String = w.text[i]
					var cell_pos: Vector2i = w.cells[i]
					var letter_pts: int = LETTER_POINTS.get(ch.to_upper(), 0)
					var mod: String = board_modifiers[cell_pos.x][cell_pos.y]
					if mod == MOD_2X:
						letter_pts *= 2
					elif mod == MOD_3X:
						letter_pts *= 3
					letter_points += letter_pts
				total += letter_points
	return total

func _score_word_sim(w: Dictionary) -> int:
	var word_points := 0
	for i in (w.text as String).length():
		var ch: String = (w.text as String)[i]
		var cell_pos: Vector2i = w.cells[i]
		var letter_pts: int = LETTER_POINTS.get(ch.to_upper(), 0)
		var mod: String = board_modifiers[cell_pos.x][cell_pos.y]
		if mod == MOD_2X:
			letter_pts *= 2
		elif mod == MOD_3X:
			letter_pts *= 3
		word_points += letter_pts
	word_points *= WORD_BONUS_MULTIPLIER
	return word_points

func _extract_word_in_direction(pos: Vector2i, dir: Vector2i) -> Dictionary:
	var start_pos := pos
	while true:
		var prev := start_pos - dir
		if prev.x < 0 or prev.x >= BOARD_SIZE or prev.y < 0 or prev.y >= BOARD_SIZE:
			break
		if board[prev.x][prev.y] == "":
			break
		start_pos = prev
	var text := ""
	var cells_arr: Array = []
	var p := start_pos
	while true:
		if p.x < 0 or p.x >= BOARD_SIZE or p.y < 0 or p.y >= BOARD_SIZE:
			break
		if board[p.x][p.y] == "":
			break
		text += board[p.x][p.y]
		cells_arr.append(p)
		p += dir
	return {"text": text, "start": start_pos, "cells": cells_arr}

func clear_board() -> void:
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			board[x][y] = ""
			board_modifiers[x][y] = MOD_NONE

func _advance_round() -> void:
	# Reset round state BEFORE advancing target, so progression is correct.
	current_round += 1
	round_score = 0
	turns_left = TURNS_PER_ROUND
	tiles_per_turn += 1
	if current_round == 2:
		_t_prev = _t_curr
		_t_curr = 30.0
		target_score = 30
	else:
		var next := _t_curr + _t_prev / 2.0
		_t_prev = _t_curr
		_t_curr = next
		target_score = int(next)
	clear_board()
