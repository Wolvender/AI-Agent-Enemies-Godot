extends CharacterBody3D

@export var speed := 4.0
@export var attack_range := 1.5
@export var chase_range := 10.0
@export var health := 100.0

@onready var animation_player: AnimationPlayer = $Visual/enemy/AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual: Node3D = $Visual/enemy

enum State { IDLE, CHASE, ATTACK, DEAD }
var current_state: State = State.IDLE
var player: CharacterBody3D = null
var is_attacking := false

func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	await get_tree().create_timer(0.1).timeout
	navigation_agent.target_position = global_position
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Enemy could not find player! Make sure Player node is in the 'player' group.")

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "mixamo_com_010":
		is_attacking = false

func _physics_process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return
	if current_state == State.DEAD:
		return
	_update_state()
	_process_state()

func _update_state() -> void:
	if health <= 0:
		_change_state(State.DEAD)
		return
	var distance = global_position.distance_to(player.global_position)
	if distance <= attack_range:
		_change_state(State.ATTACK)
	elif distance <= chase_range:
		_change_state(State.CHASE)
	else:
		_change_state(State.IDLE)

func _process_state() -> void:
	match current_state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase()
		State.ATTACK:
			_state_attack()
		State.DEAD:
			_state_dead()

func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	current_state = new_state

func _state_idle() -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	play_animation("mixamo_com_007")

func _state_chase() -> void:
	navigation_agent.target_position = player.global_position
	var next_pos = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	play_animation("mixamo_com_002")

func _state_attack() -> void:
	velocity = Vector3.ZERO
	is_attacking = true
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	play_animation("mixamo_com_010")

func _state_dead() -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	play_animation("mixamo_com_006")

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	health -= amount
	play_animation("mixamo_com")
	if health <= 0:
		_change_state(State.DEAD)

func play_animation(anim_name: String) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.2)
