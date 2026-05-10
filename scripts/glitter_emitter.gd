extends GPUParticles2D

func _ready() -> void:
	var canvas_mat := CanvasItemMaterial.new()
	canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = canvas_mat

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 100.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 2.0
	pm.scale_max = 5.0

	var grad := Gradient.new()
	grad.colors  = [Color("#00FFFF"), Color("#FF00FF"), Color("#FFD700"), Color(1, 1, 1, 0)]
	grad.offsets = [0.0, 0.3, 0.6, 1.0]
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp

	process_material = pm
	amount          = 24
	lifetime        = 0.8
	one_shot        = true
	explosiveness   = 0.95
	emitting        = true

	await get_tree().create_timer(lifetime + 0.2).timeout
	queue_free()
