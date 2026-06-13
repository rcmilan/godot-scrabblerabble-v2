extends "res://scripts/sim/strategies/word_search_strategy.gd"

const VOWELS := {"A": true, "E": true, "I": true, "O": true, "U": true}

func get_name() -> String:
	return "discard_word_search"

func pick_discards(core) -> Array:
	if core.discards_left <= 0:
		return []
	# (C) Only discard when stuck. word_search returns a multi-tile
	# placement only when it matched the dictionary; a 1-tile random
	# fallback is the "no word found" signal. (pick_moves is read-only.)
	if pick_moves(core).size() >= 2:
		return []
	# (B) Stuck -> ditch one least-useful tile to fish for a better hand.
	var letter := _least_useful_letter(core)
	return [letter] if letter != "" else []

func _least_useful_letter(core) -> String:
	var letters: Array = core.rack_letters()
	if letters.is_empty():
		return ""
	var vowels := 0
	for l in letters:
		if VOWELS.has(l):
			vowels += 1
	var want_drop_vowel := vowels >= 5     # vowel-flooded
	var want_keep_vowel := vowels <= 1     # vowel-starved
	var best := ""
	var best_freq := 999
	for l in letters:
		var is_vowel: bool = VOWELS.has(l)
		if want_keep_vowel and is_vowel:
			continue
		if want_drop_vowel and not is_vowel:
			continue
		var freq: int = core.LETTER_DISTRIBUTION.get(l, 0)
		if freq < best_freq:
			best_freq = freq
			best = l
	return best if best != "" else letters[0]
