extends CharacterBody3D

@export var speed := 6.0
@export var run_speed := 10.0
@export var jump_velocity := 5.5
@export var double_jump_velocity := 4.5
@export var double_jump_window := 0.5
@export var sensitivity := 0.2
@export var min_pitch := -60.0
@export var max_pitch := 60.0

# ==================== HEALTH SYSTEM ====================
@export var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var kill_count: int = 0

# Signal so your main scene / game manager can react
signal player_died
signal kill_count_changed(new_count: int)

# === Attack Settings ===
@export var attack_damage := 25.0
@export var attack_range := 2.0
@export var attack_cooldown := 0.6

@onready var camera_mount: Node3D = $CameraMount
@onready var animation_player: AnimationPlayer = $Visual/Player/AnimationPlayer
@onready var sword_area: Area3D = $Visual/Player/Armature/Skeleton3D/PhysicalBone3D/sword_psx/Area3D

# Health bar (HUD)
@onready var health_bar: TextureProgressBar = $SubViewport/TextureProgressBar
@onready var kill_label: Label = get_node_or_null("HUD/KillCount")
@onready var wave_label: Label = get_node_or_null("HUD/WaveCount")

var jump_count := 0
var jump_timer := 0.0
var double_jump_anim_playing := false
var is_attacking := false
var attack_timer := 0.0
var _hit_bodies := []

# Movement feel vars
var coyote_time := 0.0
const COYOTE_DURATION := 0.15
var jump_buffer := 0.0
const JUMP_BUFFER_DURATION := 0.15
var was_on_floor := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.animation_finished.connect(_on_animation_finished)
	
	current_health = max_health
	is_dead = false
	
	sword_area.body_entered.connect(_on_sword_hit)
	sword_area.monitoring = false
	
	# Setup health bar
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health

	# === PLAYER HEALTH BAR SETUP WITH DEBUG ===
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
		print("✅ Player health bar found and ready!")
	else:
		print("❌ ERROR: Player health bar NOT FOUND! Check node path $CanvasLayer/HealthBar")

	if kill_label:
		kill_label.text = "Kills: " + str(kill_count)
		print("✅ Kill count label found and ready!")
	else:
		print("❌ ERROR: Kill count label NOT FOUND! Check node path $HUD/KillCount")

	if wave_label:
		wave_label.text = "Wave: 1"
		print("✅ Wave label found and ready!")

func update_wave(wave: int) -> void:
	if wave_label:
		wave_label.text = "Wave: " + str(wave)
	print("Wave updated to: ", wave)

func _on_animation_finished(anim_name: String) -> void:

	if anim_name == "mixamo_com_017":
		double_jump_anim_playing = false
	if anim_name == "mixamo_com_010":
		is_attacking = false
		animation_player.speed_scale = 1.0

# ====================== INPUT ======================
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
func _on_sword_hit(body: Node) -> void:
	if body == self or body in _hit_bodies:
		return
	var target = body if body.has_method("take_damage") else body.get_parent()
	if target.has_method("take_damage"):
		_hit_bodies.append(body)
		print("Attempting to deal ", attack_damage, " damage to ", target.name)
		target.take_damage(attack_damage)
	else:
		print("Hit something that cannot take damage: ", body.name)

func try_attack() -> void:
	if is_attacking or attack_timer > 0.0 or not is_on_floor():
		return
	is_attacking = true
	attack_timer = attack_cooldown
	_hit_bodies.clear()
	# Lunge forward
	velocity += -global_transform.basis.z * 4.0
	animation_player.speed_scale = 2.0
	play_animation("mixamo_com_010")
	sword_area.monitoring = true
	await get_tree().create_timer(0.4).timeout
	sword_area.monitoring = false

# ====================== HEALTH & DEATH ======================
func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health = clamp(current_health - amount, 0, max_health)
	
	if health_bar:
		health_bar.value = current_health
		print("✅ Player health bar UPDATED to ", current_health, "/", max_health)
	else:
		print("❌ Player health bar reference is null - bar will not update!")
	
	print("Player took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	if current_health <= 1:
		die()

func add_kill() -> void:
	kill_count += 1
	kill_count_changed.emit(kill_count)
	
	# Scaling damage: Every 5 kills, add 10 more attack damage
	if kill_count > 0 and kill_count % 5 == 0:
		attack_damage += 10.0
		print("🔥 Damage Up! New attack damage: ", attack_damage)
		if kill_label:
			# Temporary visual feedback for damage up
			var original_text = "Kills: " + str(kill_count)
			kill_label.text = "DMG UP! " + str(attack_damage)
			await get_tree().create_timer(2.0).timeout
			if kill_label: kill_label.text = "Kills: " + str(kill_count)
	else:
		if kill_label:
			kill_label.text = "Kills: " + str(kill_count)
			
	print("Enemy killed! Total kills: ", kill_count)
		
func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	set_process_input(false)
	animation_player.speed_scale = 1.0
	animation_player.play("mixamo_com_006", 0.2)
	player_died.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://Scenes/DeathScreen.tscn")


# ====================== PHYSICS PROCESS ======================
func _physics_process(delta: float) -> void:
	if is_dead:
		move_and_slide()
		return
	
	if attack_timer > 0.0:
		attack_timer -= delta

	# Coyote time
	if was_on_floor and not is_on_floor():
		coyote_time = COYOTE_DURATION
	if coyote_time > 0:
		coyote_time -= delta
	was_on_floor = is_on_floor()

	# Jump buffer
	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer = JUMP_BUFFER_DURATION
	if jump_buffer > 0:
		jump_buffer -= delta

	if not is_on_floor():
		# Snappier gravity
		velocity += get_gravity() * delta * 1.4
	if jump_timer > 0:
		jump_timer -= delta

	if is_on_floor():
		jump_count = 0
		jump_timer = 0.0
		double_jump_anim_playing = false

	# Jump with coyote + buffer
	if jump_buffer > 0:
		if is_on_floor() or coyote_time > 0:
			velocity.y = jump_velocity
			jump_count = 1
			jump_timer = double_jump_window
			jump_buffer = 0.0
			coyote_time = 0.0
		elif jump_count == 1 and jump_timer > 0:
			velocity.y = double_jump_velocity
			jump_count = 2
			double_jump_anim_playing = true
			jump_buffer = 0.0

	if Input.is_action_just_pressed("attack") and is_on_floor() and not is_attacking:
		try_attack()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed = run_speed if Input.is_key_pressed(KEY_SHIFT) else speed

	if direction:
		if not is_attacking:
			# Smooth acceleration
			velocity.x = lerp(velocity.x, direction.x * current_speed, 0.25)
			velocity.z = lerp(velocity.z, direction.z * current_speed, 0.25)
			var target_rotation = atan2(input_dir.x, input_dir.y)
			$Visual/Player.rotation.y = lerp_angle($Visual/Player.rotation.y, target_rotation, 15.0 * delta)
		else:
			# Snappy stop while attacking
			velocity.x = move_toward(velocity.x, 0, current_speed * 0.3)
			velocity.z = move_toward(velocity.z, 0, current_speed * 0.3)
	else:
		# Snappy stop
		velocity.x = move_toward(velocity.x, 0, current_speed * 0.3)
		velocity.z = move_toward(velocity.z, 0, current_speed * 0.3)

	# Camera bob
	if is_on_floor() and direction:
		var bob_speed = 14.0 if current_speed == run_speed else 9.0
		camera_mount.position.y = sin(Time.get_ticks_msec() * 0.001 * bob_speed) * 0.035
	else:
		camera_mount.position.y = lerp(camera_mount.position.y, 0.0, 10.0 * delta)

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
