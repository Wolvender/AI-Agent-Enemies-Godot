extends CharacterBody3D

const SPEED = 5.0
const RUN_SPEED = 8.0
const JUMP_VELOCITY = 5.0
const SENSITIVITY = 0.01

@onready var mount: Node3D = $Mount
@onready var animation_player: AnimationPlayer = $Visuals/mixamo_base/AnimationPlayer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * SENSITIVITY)
		mount.rotate_x(-event.relative.y * SENSITIVITY)
		mount.rotation.x = clamp(mount.rotation.x, deg_to_rad(-60), deg_to_rad(60))

	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed = RUN_SPEED if Input.is_action_pressed("run") else SPEED

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		var target_rotation = atan2(input_dir.x, input_dir.y) + PI
		$Visuals.rotation.y = lerp_angle($Visuals.rotation.y, target_rotation, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	update_animations(direction, current_speed)

func update_animations(direction: Vector3, current_speed: float) -> void:
	if not is_on_floor():
		if velocity.y > 0.1:  # small threshold to stabilize apex
			if animation_player.current_animation != "JumpingInPlace":
				animation_player.play("JumpingInPlace", 0.15)
		else:
			if animation_player.current_animation != "Falling":
				animation_player.play("Falling", 0.5)
				
		return

	if direction != Vector3.ZERO:
		if current_speed == RUN_SPEED:
			if animation_player.current_animation != "running":
				animation_player.play("running", 0.3)
		else:
			if animation_player.current_animation != "walking":
				animation_player.play("walking", 0.3)
	else:
		if animation_player.current_animation != "idle":
			animation_player.play("idle", 0.5)
