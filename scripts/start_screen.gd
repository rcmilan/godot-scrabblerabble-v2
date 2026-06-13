extends Control

const GLITCH_FREEZE_SEC: float = 0.4
const GLITCH_HOLD_SEC:   float = 0.3
const GHOST_STEP_PX:     float = 20.0
const GHOST_STEPS:       int   = 12
const GHOST_STEP_SEC:    float = 0.06

@onready var title_dialog: Panel  = $TitleDialog
@onready var start_button: Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/StartButton
@onready var quit_button:  Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/QuitButton
@onready var close_btn:    Button = $TitleDialog/InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn
@onready var subtitle:     Label  = $TitleDialog/InnerVBox/BodyArea/Subtitle

var _launching: bool = false

func _ready() -> void:
	var vp_size := Vector2(get_viewport_rect().size)
	title_dialog.position = (vp_size - title_dialog.custom_minimum_size) / 2.0
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	close_btn.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()
	_set_random_subtitle()
	print("[StartScreen] ready — menu shown")
	_maybe_autoplay()

func _set_random_subtitle() -> void:
	# GameData may be unavailable in unusual launch paths; keep the scene's
	# static subtitle as the fallback.
	var game_data := get_node_or_null("/root/GameData")
	if game_data == null or game_data.valid_words.is_empty():
		return
	var all_words: Array = game_data.valid_words.keys()
	var picked: Array[String] = []
	while picked.size() < 3:
		var w: String = all_words.pick_random()
		if not picked.has(w):
			picked.append(w)
	subtitle.text = " · ".join(picked)
	print("[StartScreen] subtitle words — %s" % ", ".join(picked))

func _on_start_pressed() -> void:
	if _launching:
		return
	_launching = true
	start_button.disabled = true
	quit_button.disabled = true
	_play_launch_glitch()

func _play_launch_glitch() -> void:
	await get_tree().create_timer(GLITCH_FREEZE_SEC).timeout
	var ghost_count := 0
	for i in GHOST_STEPS:
		var ghost := title_dialog.duplicate() as Panel
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.set_process(false)
		ghost.set_process_input(false)
		$GhostLayer.add_child(ghost)
		# The duplicate inherits TitleDialog's center anchors; reset to
		# top-left so position is absolute, or the anchor math re-adds
		# the parent's center and dumps the ghost at the bottom-right.
		ghost.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ghost.position = title_dialog.position
		ghost.size = title_dialog.size
		ghost_count += 1
		if i % 2 == 0:
			title_dialog.position.x += GHOST_STEP_PX
		else:
			title_dialog.position.y += GHOST_STEP_PX
		await get_tree().create_timer(GHOST_STEP_SEC).timeout
	print("[StartScreen] launch glitch — %d ghosts stamped" % ghost_count)
	await get_tree().create_timer(GLITCH_HOLD_SEC).timeout
	_launch()

func _launch() -> void:
	print("[StartScreen] launching main scene")
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed() -> void:
	if _launching:
		return
	print("[StartScreen] quit")
	get_tree().quit()

func _has_autoplay_arg() -> bool:
	for raw in OS.get_cmdline_user_args():
		if raw == "--autoplay" or raw.begins_with("--autoplay="):
			return true
	return false

func _maybe_autoplay() -> void:
	if not _has_autoplay_arg():
		return
	if RunState.autoplay_run_completed:
		print("[StartScreen] run complete — quitting")
		get_tree().quit()
		return
	print("[StartScreen] autoplay detected — pressing Start")
	await get_tree().create_timer(0.3).timeout
	_on_start_pressed()
