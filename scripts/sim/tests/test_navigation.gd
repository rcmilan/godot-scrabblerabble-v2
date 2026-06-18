class_name TestNavigation
extends RefCounted

const Navigation = preload("res://scripts/navigation.gd")

# TN1 - The reported bug: right at the right edge (top row) must NOT move up.
func test_tn1_right_edge_top_row_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 0))
	nav.move(Vector2i(1, 0), 7)
	if nav.board_pos != Vector2i(7, 0):
		push_error("TN1: expected (7,0), got %s" % nav.board_pos); return false
	if nav.region != Navigation.Region.BOARD:
		push_error("TN1: expected region BOARD"); return false
	return true

# TN2 - Right at the right edge (bottom row) also clamps, no y change.
func test_tn2_right_edge_bottom_row_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 7))
	nav.move(Vector2i(1, 0), 7)
	if nav.board_pos != Vector2i(7, 7):
		push_error("TN2: expected (7,7), got %s" % nav.board_pos); return false
	return true

# TN3 - Down on the bottom row enters the rack at the matching column.
func test_tn3_bottom_down_enters_rack() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(4, 7))
	nav.move(Vector2i(0, 1), 7)
	if nav.region != Navigation.Region.RACK:
		push_error("TN3: expected region RACK"); return false
	if nav.rack_index != 4:
		push_error("TN3: expected rack_index 4, got %d" % nav.rack_index); return false
	return true

# TN4 - Entering a narrower rack clamps the index.
func test_tn4_bottom_down_clamps_to_rack_size() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(7, 7))
	nav.move(Vector2i(0, 1), 3)
	if nav.rack_index != 2:
		push_error("TN4: expected rack_index 2, got %d" % nav.rack_index); return false
	return true

# TN5 - Up from the rack returns to the board, anchor unchanged.
func test_tn5_rack_up_returns_to_anchor() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(2, 7))
	nav.move(Vector2i(0, 1), 7)        # into rack
	nav.move(Vector2i(0, -1), 7)       # back up
	if nav.region != Navigation.Region.BOARD:
		push_error("TN5: expected region BOARD"); return false
	if nav.board_pos != Vector2i(2, 7):
		push_error("TN5: expected anchor (2,7), got %s" % nav.board_pos); return false
	return true

# TN6 - Down in the rack is a no-op.
func test_tn6_rack_down_noop() -> bool:
	var nav = Navigation.new()
	nav.set_rack(3)
	nav.move(Vector2i(0, 1), 7)
	if nav.region != Navigation.Region.RACK or nav.rack_index != 3:
		push_error("TN6: expected RACK index 3, got region %d index %d" % [nav.region, nav.rack_index]); return false
	return true

# TN7 - Rack left/right clamps within [0, rack_size-1].
func test_tn7_rack_left_right_clamps() -> bool:
	var nav = Navigation.new()
	nav.set_rack(0)
	nav.move(Vector2i(-1, 0), 7)       # cannot go below 0
	if nav.rack_index != 0:
		push_error("TN7: expected 0, got %d" % nav.rack_index); return false
	nav.set_rack(6)
	nav.move(Vector2i(1, 0), 7)        # cannot exceed 6
	if nav.rack_index != 6:
		push_error("TN7: expected 6, got %d" % nav.rack_index); return false
	return true

# TN8 - Interior moves shift board_pos by one without changing region.
func test_tn8_interior_moves() -> bool:
	var nav = Navigation.new()
	nav.set_board(Vector2i(3, 3))
	nav.move(Vector2i(1, 0), 7)
	nav.move(Vector2i(0, 1), 7)
	if nav.board_pos != Vector2i(4, 4):
		push_error("TN8: expected (4,4), got %s" % nav.board_pos); return false
	if nav.region != Navigation.Region.BOARD:
		push_error("TN8: expected region BOARD"); return false
	return true
