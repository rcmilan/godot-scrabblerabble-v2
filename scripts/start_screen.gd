extends Control

@onready var title_dialog: Panel  = $TitleDialog
@onready var start_button: Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/StartButton
@onready var quit_button:  Button = $TitleDialog/InnerVBox/BodyArea/ButtonRow/QuitButton
@onready var close_btn:    Button = $TitleDialog/InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn

var _launching: bool = false

func _ready() -> void:
	var vp_size := Vector2(get_viewport_rect().size)
	title_dialog.position = (vp_size - title_dialog.custom_minimum_size) / 2.0
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	close_btn.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()
	print("[StartScreen] ready — menu shown")
	_maybe_autoplay()

func _on_start_pressed() -> void:
	if _launching:
		return
	_launching = true
	start_button.disabled = true
	quit_button.disabled = true
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
