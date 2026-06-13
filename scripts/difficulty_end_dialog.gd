extends Panel

var _won: bool = false
var _final_round: int = 0
var _total: int = 0
var _best: int = 0
var _is_new: bool = false

func setup(won: bool, final_round: int, total: int, best: int, is_new: bool) -> void:
	_won = won
	_final_round = final_round
	_total = total
	_best = best
	_is_new = is_new

func _ready() -> void:
	$InnerVBox/TitleBar/TitleContent/TitleLabel.text = "You Win!" if _won else "Game Over"
	$InnerVBox/BodyArea/ResultLabel.text = "You cleared all 5 rounds!" if _won else "Failed at round %d of 5" % _final_round
	$InnerVBox/BodyArea/ScoreLabel.text = "Score: %d" % _total
	$InnerVBox/BodyArea/BestLabel.text = "Best (%s): %d" % [RunState.mode_name(), _best]
	$InnerVBox/BodyArea/NewHighLabel.visible = _is_new
	$InnerVBox/BodyArea/ButtonRow/PlayAgainButton.pressed.connect(_on_play_again)
	$InnerVBox/BodyArea/ButtonRow/MenuButton.pressed.connect(_on_menu)
	$InnerVBox/TitleBar/TitleContent/WinButtons/CloseBtn.pressed.connect(_on_menu)
	$InnerVBox/BodyArea/ButtonRow/PlayAgainButton.grab_focus()

func _on_play_again() -> void:
	print("[DifficultyEndDialog] play again")
	RunState.reset()
	get_tree().reload_current_scene()

func _on_menu() -> void:
	print("[DifficultyEndDialog] menu")
	RunState.reset()
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
