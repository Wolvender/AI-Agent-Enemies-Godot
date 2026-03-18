extends CharacterBody3D

@export var speed := 5.0
@export var run_speed := 8.0
@export var jump_velocity := 4.5
@export var double_jump_velocity := 4.0
@export var double_jump_window := 0.5 # 0.5 seconds to press jump again
@export var sensitivity := 0.2
@export var min_pitch := -60.0
@export var max_pitch := 60.0

@onready var camera_mount: Node3D = $CameraMount
@onready var animation_player: AnimationPlayer = $Visual/allAnims/AnimationPlayer

var jump_count := 0
var jump_timer := 0.0

func _ready() -> void:
	# Keep the mouse stuck in the window
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Look around with the mouse
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		if camera_mount:
			camera_mount.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
			camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

	# Press Escape to release the mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
		if jump_timer > 0:
			jump_timer -= delta
	else:
		jump_count = 0
		jump_timer = 0.0

	# Handle Jump
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			velocity.y = jump_velocity
			jump_count = 1
			jump_timer = double_jump_window
		elif jump_count == 1 and jump_timer > 0:
			velocity.y = double_jump_velocity
			jump_count = 2
			play_animation("mixamo_com_003")

	# Get WASD input (using default Godot actions)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine speed (Shift for running)
	var current_speed = run_speed if Input.is_key_pressed(KEY_SHIFT) else speed
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		# Rotate the visual model to face the direction of movement
		var target_rotation = atan2(input_dir.x, input_dir.y)
		$Visual.rotation.y = lerp_angle($Visual.rotation.y, target_rotation, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	
	update_animations(direction, current_speed)

func update_animations(direction: Vector3, current_speed: float) -> void:
	if not is_on_floor():
		if jump_count == 2:
			# We already triggered double jump animation in physics_process
			return
			
		if velocity.y > 0:
			# mixamo_com_005 is jumping
			play_animation("mixamo_com_005")
		else:
			# mixamo_com is falling
			play_animation("mixamo_com")
		return

	if direction:
		if current_speed == run_speed:
			# mixamo_com_001 is running
			play_animation("mixamo_com_001")
		else:
			# mixamo_com_007 is walking
			play_animation("mixamo_com_007")
	else:
		# mixamo_com_002 is idle
		play_animation("mixamo_com_002")

func play_animation(anim_name: String) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.2) # 0.2s crossfade for smoothness
