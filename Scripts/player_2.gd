extends CharacterBody3D

@export var speed := 5.0
@export var run_speed := 8.0
@export var jump_velocity := 4.5
@export var double_jump_velocity := 4.0
@export var double_jump_window := 0.5
@export var sensitivity := 0.2
@export var min_pitch := -60.0
@export var max_pitch := 60.0

# === NEW: Health System ===
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var is_dead: bool = false

@onready var camera_mount: Node3D = $CameraMount
@onready var animation_player: AnimationPlayer = $Visual/Player/AnimationPlayer

var jump_count := 0
var jump_timer := 0.0
var double_jump_anim_playing := false
var is_attacking := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.animation_finished.connect(_on_animation_finished)
	
	# Make sure health starts at max
	current_health = max_health

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "mixamo_com_017":
		double_jump_anim_playing = false
	if anim_name == "mixamo_com_010":
		is_attacking = false

func _input(event: InputEvent) -> void:
	if is_dead:
		return  # Disable input when dead
	
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		if camera_mount:
			camera_mount.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
			camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# New function to take damage
func take_damage(amount: float) -> void:
	if is_dead:
		return
	
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	
	print("Player took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	if current_health <= 0:
		die()

func die() -> void:
	is_dead = true
	print("Player died!")
	
	# Stop all movement
	velocity = Vector3.ZERO
	
	# Optional: Play death animation if you have one
	# animation_player.play("death_animation")
	
	# You can add more death logic here (respawn timer, game over screen, etc.)

func _physics_process(delta: float) -> void:
	if is_dead:
		move_and_slide()  # Keep sliding to a stop if needed
		return
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	if jump_timer > 0:
		jump_timer -= delta

	# Reset jump count when on floor
	if is_on_floor():
		jump_count = 0
		jump_timer = 0.0
		double_jump_anim_playing = false

	# Jump logic
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			velocity.y = jump_velocity
			jump_count = 1
			jump_timer = double_jump_window
		elif jump_count == 1 and jump_timer > 0:
			velocity.y = double_jump_velocity
			jump_count = 2
			double_jump_anim_playing = true

	# Attack (only on floor and not attacking)
	if Input.is_action_just_pressed("attack") and is_on_floor() and not is_attacking:
		is_attacking = true
		# You can add attack damage here later if needed

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = run_speed if Input.is_key_pressed(KEY_SHIFT) else speed

	if direction:
		if not is_attacking:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
			
			var target_rotation = atan2(input_dir.x, input_dir.y)
			$Visual/Player.rotation.y = lerp_angle($Visual/Player.rotation.y, target_rotation, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	update_animations(direction, current_speed)

func update_animations(direction: Vector3, current_speed: float) -> void:
	if is_dead:
		# Optional: play death animation
		return
	
	if not is_on_floor():
		if double_jump_anim_playing:
			play_animation("mixamo_com_017")
			return
		if velocity.y > 0:
			play_animation("mixamo_com_005")
		else:
			play_animation("mixamo_com_001")
		return

	if is_attacking:
		play_animation("mixamo_com_010")
		return

	if direction:
		if current_speed == run_speed:
			play_animation("mixamo_com_002")
		else:
			play_animation("mixamo_com_011")
	else:
		play_animation("mixamo_com_007")

func play_animation(anim_name: String) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.2)
