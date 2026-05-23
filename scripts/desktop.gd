# res://scripts/desktop.gd
extends CanvasLayer

signal resume_requested

func _ready() -> void:
	# Ensure background covers the full viewport
	var background := $Background
	if background:
		background.size = get_viewport().get_visible_rect().size

	# Set up icon signal connections
	$Mod2xIcon.activated.connect(_on_mod2x_activated)
	$ScrabblerabbleIcon.activated.connect(_on_scrabblerabble_activated)

func _on_mod2x_activated(icon_id: StringName) -> void:
	if icon_id == &"mod_2x":
		RunState.add_to_build(GameData.MOD_2X)
		$Mod2xIcon._flash_feedback()

func _on_mod2x_dropped() -> void:
	# Called when mod-2x is dropped onto the user folder
	RunState.add_to_build(GameData.MOD_2X)
	$Mod2xIcon._flash_feedback()

func _on_scrabblerabble_activated(icon_id: StringName) -> void:
	if icon_id == &"scrabblerabble":
		resume_requested.emit()
