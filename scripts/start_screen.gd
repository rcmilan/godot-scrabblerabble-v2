extends Control

const GLITCH_FREEZE_SEC: float = 0.4
const GLITCH_HOLD_SEC:   float = 0.3
const GHOST_STEP_PX:     float = 20.0
const GHOST_STEPS:       int   = 12
const GHOST_STEP_SEC:    float = 0.06

@onready var title_dialog:   Panel  = $TitleDialog
@onready var easy_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/EasyButton
@onready var medium_button:  Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/MediumButton
@onready var hard_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/HardButton
@onready var endless_button: Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/EndlessButton
@onready var quit_button:    Button = $TitleDialog/InnerVBox/BodyArea/MenuButtons/QuitButton
@onready var close_btn:      Button = $TitleDialog/InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn
@onready var subtitle:       Label  = $TitleDialog/InnerVBox/BodyArea/Subtitle

var _launching: bool = false

func _ready() -> void:
	var vp_size := Vector2(get_viewport_rect().size)
	title_dialog.position = (vp_size - title_dialog.custom_minimum_size) / 2.0
	easy_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.EASY))
	medium_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.MEDIUM))
	hard_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.HARD))
	endless_button.pressed.connect(func() -> void: _on_mode_selected(RunState.Mode.ENDLESS))
	quit_button.pressed.connect(_on_quit_pressed)
	close_btn.pressed.connect(_on_quit_pressed)
	easy_button.grab_focus()
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

func _on_mode_selected(mode: int) -> void:
	if _launching:
		return
	_launching = true
	easy_button.disabled = true
	medium_button.disabled = true
	hard_button.disabled = true
	endless_button.disabled = true
	quit_button.disabled = true
	RunState.mode = mode
	print("[StartScreen] mode selected — %s" % RunState.mode_name())
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
	print("[StartScreen] autoplay detected — launching Endless")
	await get_tree().create_timer(0.3).timeout
	_on_mode_selected(RunState.Mode.ENDLESS)
