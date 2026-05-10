# res://scripts/game_data.gd
extends Node

# Standard Scrabble letter point values (English).
const LETTER_POINTS: Dictionary = {
	"A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2,
	"H": 4, "I": 1, "J": 8, "K": 5, "L": 1, "M": 3, "N": 1,
	"O": 1, "P": 3, "Q": 10, "R": 1, "S": 1, "T": 1, "U": 1,
	"V": 4, "W": 4, "X": 8, "Y": 4, "Z": 10,
}

# Standard Scrabble tile distribution (English, 100 tiles, blanks omitted).
const LETTER_DISTRIBUTION: Dictionary = {
	"A": 9, "B": 2, "C": 2, "D": 4, "E": 12, "F": 2, "G": 3,
	"H": 2, "I": 9, "J": 1, "K": 1, "L": 4, "M": 2, "N": 6,
	"O": 8, "P": 2, "Q": 1, "R": 6, "S": 4, "T": 6, "U": 4,
	"V": 2, "W": 2, "X": 1, "Y": 2, "Z": 1,
}

# Hash-set of valid English words (uppercase).
var valid_words: Dictionary = {}

func _ready() -> void:
	_load_dictionary("res://data/words.txt")

func _load_dictionary(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Dictionary file not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	# Split by line endings, normalize, skip empties and very short tokens.
	for raw in text.split("\n"):
		var w := raw.strip_edges().to_upper()
		if w.length() >= 2 and w.length() <= 8:
			valid_words[w] = true
	print("Dictionary loaded: %d words" % valid_words.size())

func is_valid_word(word: String) -> bool:
	return valid_words.has(word.to_upper())

func score_for_letter(letter: String) -> int:
	return LETTER_POINTS.get(letter.to_upper(), 0)
