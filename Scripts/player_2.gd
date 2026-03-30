extends CharacterBody3D

@export var speed := 5.0
@export var run_speed := 8.0
@export var jump_velocity := 4.5
@export var double_jump_velocity := 4.0
@export var double_jump_window := 0.5
@export var sensitivity := 0.2
@export var min_pitch := -60.0
@export var max_pitch := 60.0

# === Health System ===
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var is_dead: bool = false

# === Attack Settings ===
@export var attack_damage := 25.0                    # How much damage you deal
@export var attack_range := 2.0                      # How far your attack reaches
@export var attack_cooldown := 0.6                   # Time between attacks (seconds)

@onready var camera_mount: Node3D = $CameraMount
@onready var animation_player: AnimationPlayer = $Visual/Player/AnimationPlayer

var jump_count := 0
var jump_timer := 0.0
var double_jump_anim_playing := false
var is_attacking := false
var attack_timer := 0.0   # Prevents spamming attacks

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.animation_finished.connect(_on_animation_finished)
	current_health = max_health


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "mixamo_com_017":
		double_jump_anim_playing = false
	if anim_name == "mixamo_com_010":
		is_attacking = false


func _input(event: InputEvent) -> void:
	if is_dead:
		return
		
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


# ====================== ATTACK SYSTEM ======================
func try_attack() -> void:
	if is_attacking or attack_timer > 0.0 or not is_on_floor():
		return
	
	is_attacking = true
	attack_timer = attack_cooldown
	
	# Play attack animation
	play_animation("mixamo_com_010")
	
	# Deal damage at the right moment (we'll use a timer for better timing)
	await get_tree().create_timer(0.3).timeout   # Adjust this value to match your punch/kick timing
	
	if is_attacking:  # Still attacking (not interrupted)
		_perform_melee_attack()


func _perform_melee_attack() -> void:
	var space_state = get_world_3d().direct_space_state
	var from = global_position + Vector3(0, 1.0, 0)           # roughly chest height
	var forward = -global_transform.basis.z                   # forward direction
	
	var to = from + forward * attack_range
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(attack_damage)
			print("Player hit ", result.collider.name, " for ", attack_damage, " damage!")
		elif result.collider.is_in_group("enemy"):   # fallback
			if result.collider.has_method("take_damage"):
				result.collider.take_damage(attack_damage)


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
	velocity = Vector3.ZERO
	# animation_player.play("death")  # Uncomment when you have a death animation


func _physics_process(delta: float) -> void:
	if is_dead:
		move_and_slide()
		return
	
	# Update attack cooldown
	if attack_timer > 0.0:
		attack_timer -= delta
	
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	if jump_timer > 0:
		jump_timer -= delta
	
	if is_on_floor():
		jump_count = 0
		jump_timer = 0.0
		double_jump_anim_playing = false
	
	# === INPUT ===
	if Input.is_action_just_pressed("ui_accept"):   # Jump
		if is_on_floor():
			velocity.y = jump_velocity
			jump_count = 1
			jump_timer = double_jump_window
		elif jump_count == 1 and jump_timer > 0:
			velocity.y = double_jump_velocity
			jump_count = 2
			double_jump_anim_playing = true
	
	# === ATTACK ===
	if Input.is_action_just_pressed("attack") and is_on_floor() and not is_attacking:
		try_attack()
	
	# Movement
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
