extends CharacterBody3D

@export var speed := 5.0
@export var jump_velocity := 4.5
@export var sensitivity := 0.2
@export var min_pitch := -60.0
@export var max_pitch := 60.0

@onready var camera_mount: Node3D = $CameraMount

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

	# Handle Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get WASD input (using default Godot actions or UI actions)
	# If you haven't set up "move_forward" etc, ui_up/down/left/right map to arrows/WASD by default in new projects
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
