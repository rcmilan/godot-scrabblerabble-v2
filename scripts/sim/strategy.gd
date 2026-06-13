class_name Strategy
extends RefCounted

# Base class for simulation strategies. Subclasses must implement pick_moves.

# Pick moves for this turn.
# Returns an array of dicts: [{"letter": "A", "pos": Vector2i(3, 4)}, ...]
# Length must be <= core.tiles_per_turn.
# Empty array means "pass this turn" (turn still counts).
func pick_moves(core) -> Array:
	return []

# Pick discards for this turn (before placing).
# Returns an array of letters to discard: ["A", "B", ...]
# Default empty — existing strategies never discard.
func pick_discards(core) -> Array:
	return []

func get_name() -> String:
	return "base"
