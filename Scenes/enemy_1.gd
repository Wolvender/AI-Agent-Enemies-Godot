extends CharacterBody3D

@export var speed := 4.0
@export var attack_range := 1.5
@export var chase_range := 10.0
@export var health := 100.0
@export var max_health := 100.0
@export var patrol_wait_time := 2.0

@onready var animation_player: AnimationPlayer = $Visual/enemy/AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual: Node3D = $Visual/enemy
@onready var http_request: HTTPRequest = $HTTPRequest
@onready var thought_label: Label3D = $ThoughtLabel
@onready var thought_timer: Timer = $ThoughtTimer

const ANIM_IDLE   = "mixamo_com_007"
const ANIM_WALK   = "mixamo_com_011"
const ANIM_RUN    = "mixamo_com_002"
const ANIM_ATTACK = "mixamo_com_010"
const ANIM_HIT    = "mixamo_com"
const ANIM_DEAD   = "mixamo_com_006"

const GROQ_API_KEY = preload("res://Scripts/Api_KEYS.gd").GROQ_API_KEY
const GROQ_URL            = "https://api.groq.com/openai/v1/chat/completions"
const THOUGHT_DISPLAY_TIME := 4.0
const MAX_MEMORY_ENTRIES  = 10

# ---------------------------------------------------------------------------
# State enum — new: RETREAT, STRAFE, SEEK_COVER, LISTEN
# ---------------------------------------------------------------------------
enum State { IDLE, PATROL, CHASE, ATTACK, UNSTUCK, SEARCH, RETREAT, STRAFE, SEEK_COVER, LISTEN, DEAD }
var current_state: State = State.IDLE
var player: CharacterBody3D = null
var is_attacking := false
var can_see_player := false
var time_in_state := 0.0

var ai_timer := 0.0
var ai_cooldown := 5
var waiting_for_ai := false

var patrol_points: Array = []
var current_patrol_index := 0
var patrol_wait_timer := 0.0
var is_waiting_at_point := false

var last_position := Vector3.ZERO
var stuck_timer := 0.0
var stuck_threshold := 1.5
var stuck_distance := 0.8
var unstuck_timer := 0.0
var unstuck_duration := 1.2
var unstuck_side := 1.0
var position_check_timer := 0.0
var position_check_interval := 0.5

var search_timer := 0.0
var search_duration := 6.0
var search_walk_timer := 0.0
var search_walk_duration := 1.5
var search_look_timer := 0.0
var search_look_duration := 2.0
var search_is_walking := false
var search_direction := Vector3.ZERO
var last_known_player_pos := Vector3.ZERO

# ---------------------------------------------------------------------------
# New state vars
# ---------------------------------------------------------------------------
var retreat_timer := 0.0
var retreat_duration := 2.5

var strafe_timer := 0.0
var strafe_duration := 2.0
var strafe_direction := 1.0

var cover_target := Vector3.ZERO
var cover_timer := 0.0
var cover_duration := 4.0
var cover_found := false

var listen_timer := 0.0
var listen_duration := 3.0

# ---------------------------------------------------------------------------
# Memory system — rolling log of last MAX_MEMORY_ENTRIES decisions
# ---------------------------------------------------------------------------
var memory: Array = []

func _add_memory(entry: String) -> void:
	var timestamp = snappedf(Time.get_ticks_msec() / 1000.0, 0.1)
	memory.append("[t=%.1fs] %s" % [timestamp, entry])
	if memory.size() > MAX_MEMORY_ENTRIES:
		memory.pop_front()

func _get_memory_block() -> String:
	if memory.is_empty():
		return "  (no memory yet)"
	return "  " + "\n  ".join(memory)


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	http_request.request_completed.connect(_on_request_completed)
	thought_timer.wait_time = THOUGHT_DISPLAY_TIME
	thought_timer.one_shot = true
	thought_timer.timeout.connect(_on_thought_timer_timeout)
	thought_label.visible = false
	thought_label.modulate = Color(1, 1, 1, 0)

	await get_tree().create_timer(0.1).timeout
	navigation_agent.target_position = global_position
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.5
	navigation_agent.avoidance_enabled = true

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("Enemy: Could not find player! Is the player in the 'player' group?")
	else:
		print("Enemy: Player found -> ", player.name)

	_generate_patrol_points()
	last_position = global_position
	_add_memory("Spawned and began patrol")


func _generate_patrol_points() -> void:
	var spawn = global_position
	var patrol_radius = 5.0
	patrol_points = [
		spawn + Vector3(patrol_radius, 0, 0),
		spawn + Vector3(0, 0, patrol_radius),
		spawn + Vector3(-patrol_radius, 0, 0),
		spawn + Vector3(0, 0, -patrol_radius),
	]
	print("Enemy: Generated ", patrol_points.size(), " patrol points")


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == ANIM_ATTACK:
		is_attacking = false


# ---------------------------------------------------------------------------
# Thought bubble
# ---------------------------------------------------------------------------

func _show_thought(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	thought_label.text = text
	thought_label.visible = true
	var tween = create_tween()
	tween.tween_property(thought_label, "modulate", Color(1, 1, 1, 1), 0.3)
	thought_timer.stop()
	thought_timer.start()


func _on_thought_timer_timeout() -> void:
	var tween = create_tween()
	tween.tween_property(thought_label, "modulate", Color(1, 1, 1, 0), 0.5)
	await tween.finished
	thought_label.visible = false


# ---------------------------------------------------------------------------
# Line of sight
# ---------------------------------------------------------------------------

func _check_line_of_sight() -> bool:
	if player == null:
		return false
	var space_state = get_world_3d().direct_space_state
	var from = global_position + Vector3(0, 1.0, 0)
	var to   = player.global_position + Vector3(0, 1.0, 0)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result.is_empty() or result.collider == player


# ---------------------------------------------------------------------------
# Cover detection — find nearby point that breaks LOS to player
# ---------------------------------------------------------------------------

func _find_cover_point() -> Vector3:
	var best := global_position
	var best_score := -1.0
	var to_player := (player.global_position - global_position).normalized()
	var space_state := get_world_3d().direct_space_state

	for i in range(8):
		var angle = (TAU / 8.0) * i
		var dir = Vector3(cos(angle), 0, sin(angle))
		var candidate = global_position + dir * 4.0

		var query = PhysicsRayQueryParameters3D.create(
			candidate + Vector3(0, 1, 0),
			player.global_position + Vector3(0, 1, 0)
		)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		var has_cover = not result.is_empty() and result.collider != player

		var away_score = -dir.dot(to_player)
		var score = (2.0 if has_cover else 0.0) + away_score
		if score > best_score:
			best_score = score
			best = candidate

	return best


# ---------------------------------------------------------------------------
# Physics process
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return
	if current_state == State.DEAD:
		return

	time_in_state += delta

	var prev_sight = can_see_player
	can_see_player = _check_line_of_sight()

	if prev_sight and not can_see_player and current_state == State.CHASE:
		print("Enemy: Lost sight of player! Starting search...")
		last_known_player_pos = player.global_position
		_add_memory("Lost sight of player near %s, switching to SEARCH" % str(last_known_player_pos.snapped(Vector3.ONE)))
		_change_state(State.SEARCH)

	if can_see_player and current_state == State.SEARCH:
		print("Enemy: Found player again! Chasing!")
		_add_memory("Reacquired player during SEARCH, switching to CHASE")
		_change_state(State.CHASE)

	ai_timer += delta
	if ai_timer >= ai_cooldown and not waiting_for_ai:
		ai_timer = 0.0
		_ask_ai()

	_check_if_stuck(delta)
	_process_state(delta)


func _reset_search() -> void:
	search_timer = 0.0
	search_walk_timer = 0.0
	search_look_timer = 0.0
	search_is_walking = false
	search_direction = (last_known_player_pos - global_position).normalized()
	print("Enemy: Search started, heading to last known position")


# ---------------------------------------------------------------------------
# Stuck detection
# ---------------------------------------------------------------------------

func _check_if_stuck(delta: float) -> void:
	if current_state != State.CHASE:
		stuck_timer = 0.0
		last_position = global_position
		position_check_timer = 0.0
		return

	if global_position.distance_to(player.global_position) <= attack_range * 1.5:
		stuck_timer = 0.0
		last_position = global_position
		return

	position_check_timer += delta
	if position_check_timer < position_check_interval:
		return
	position_check_timer = 0.0

	if global_position.distance_to(last_position) < stuck_distance:
		stuck_timer += position_check_interval
		if stuck_timer >= stuck_threshold:
			print("Enemy: STUCK detected! Telling AI...")
			_add_memory("Got stuck on obstacle while chasing player")
			stuck_timer = 0.0
			ai_timer = ai_cooldown
	else:
		stuck_timer = 0.0
	last_position = global_position


# ---------------------------------------------------------------------------
# AI request
# ---------------------------------------------------------------------------

func _ask_ai() -> void:
	if current_state == State.DEAD:
		return

	var distance       = global_position.distance_to(player.global_position)
	var health_percent = (health / max_health) * 100.0
	var stuck_info     = "YES - blocked by obstacle" if stuck_timer >= stuck_threshold else "NO"
	var sight_info     = "YES" if can_see_player else "NO"

	var to_player    = (player.global_position - global_position).normalized()
	var enemy_fwd    = -global_transform.basis.z.normalized()
	var player_front = "YES" if enemy_fwd.dot(to_player) > 0.5 else "NO"

	var height_diff  = abs(player.global_position.y - global_position.y)
	var same_level   = "YES" if height_diff < 1.5 else "NO (player is on different level)"

	var player_vel_flat := Vector3(player.velocity.x, 0, player.velocity.z)
	var player_moving   := "YES (speed %.1f)" % player_vel_flat.length() if player_vel_flat.length() > 0.5 else "NO (standing still)"

	print("--------------------------------------------------")
	print("Enemy: Asking AI for decision...")

	var prompt = """
You are the persistent, unhinged brain of an enemy in a 3D action game.
You remember everything that has happened this session and use that knowledge to make smarter decisions.

=== YOUR MEMORY (last %d events) ===
%s

=== CURRENT SITUATION ===
- Health: %s%% (max 100)
- Distance to player: %s units
- Current state: %s
- Time in this state: %s seconds
- Can see player: %s
- Player directly in front: %s
- Player on same level: %s
- Player is moving: %s
- Stuck on obstacle: %s
- Attack range: %s | Chase range: %s

=== YOUR TOOLS (states you can switch to) ===
IDLE       - stop and do nothing, recover
PATROL     - walk your patrol route
CHASE      - run directly at the player
ATTACK     - melee the player (only works in attack range, player in front, same level)
UNSTUCK    - strafe sideways around an obstacle
SEARCH     - investigate last known player position
RETREAT    - back away from player to create distance (good when hurt or overwhelmed)
STRAFE     - circle-strafe around the player (good to get a better angle before attacking)
SEEK_COVER - move to nearby geometry that blocks line of sight (good when health is low)
LISTEN     - stand still and detect player by sound (good after losing sight)

=== DECISION RULES ===
- Use your MEMORY. If you have been stuck multiple times, try SEEK_COVER or STRAFE instead.
- If health < 30%%: strongly consider RETREAT or SEEK_COVER before attacking again.
- If player keeps escaping: try STRAFE to cut off their angle.
- If you lost the player and SEARCH failed: try LISTEN before giving up to patrol.
- If stuck: UNSTUCK first, but if stuck repeatedly in memory, try a completely different approach.
- Do NOT keep repeating the same failing state. Your memory shows what has not worked.
- You are allowed to be creative and tactical. You are not just reacting, you are THINKING.

=== THOUGHT RULES ===
- Max 8 words, in character, unhinged villain energy
- Pull from: threatening, petty, philosophical, delusional, manic, sarcastic, exhausted, triumphant
- You may reference your own memory if dramatic (e.g. "that wall beat me twice. not again.")
- Never use quote marks in the thought text
- Be surprising. Never repeat a thought.

Respond with ONLY this format, nothing else:
STATE|thought text here

Example: STRAFE|circling you like a shark. a very tired shark.
""" % [MAX_MEMORY_ENTRIES, _get_memory_block(),
	   snappedf(health_percent, 0.1), snappedf(distance, 0.1), State.keys()[current_state],
	   snappedf(time_in_state, 0.1), sight_info, player_front, same_level, player_moving,
	   stuck_info, attack_range, chase_range]

	var body = JSON.stringify({
		"model": "llama-3.3-70b-versatile",
		"messages": [{"role": "user", "content": prompt}],
		"max_tokens": 40,
		"temperature": 1.2
	})

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + GROQ_API_KEY
	]

	print("Enemy: Sending request to Groq API...")
	var error = http_request.request(GROQ_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("Enemy: ERROR sending request -> ", error)
	else:
		waiting_for_ai = true
		print("Enemy: Request sent! Waiting for response...")


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	waiting_for_ai = false
	print("Enemy: Response received!")

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Enemy: Request failed - result: ", result, " code: ", response_code)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("Enemy: Could not parse JSON response")
		return

	var response = json.get_data()
	var raw      = response["choices"][0]["message"]["content"].strip_edges()
	print("Enemy: Raw AI response -> ", raw)
	var parts    = raw.split("|")
	var decision = parts[0].strip_edges().to_upper()
	var thought  = parts[1].strip_edges() if parts.size() > 1 else ""

	print("Enemy: AI state   -> ", decision)
	print("Enemy: AI thought -> ", thought)

	if not thought.is_empty():
		_show_thought(thought)

	var distance       = global_position.distance_to(player.global_position)
	var health_percent = (health / max_health) * 100.0
	_add_memory("Decided %s | hp=%.0f%% dist=%.1f | thought: '%s'" % [decision, health_percent, distance, thought])

	match decision:
		"IDLE":       _change_state(State.IDLE)
		"PATROL":     _change_state(State.PATROL)
		"CHASE":      _change_state(State.CHASE)
		"ATTACK":     _change_state(State.ATTACK)
		"UNSTUCK":    _change_state(State.UNSTUCK)
		"SEARCH":     _change_state(State.SEARCH)
		"RETREAT":    _change_state(State.RETREAT)
		"STRAFE":     _change_state(State.STRAFE)
		"SEEK_COVER": _change_state(State.SEEK_COVER)
		"LISTEN":     _change_state(State.LISTEN)
		_:
			print("Enemy: WARNING - Unexpected response: '", decision, "' keeping current state")

	print("--------------------------------------------------")


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

func _process_state(delta: float) -> void:
	match current_state:
		State.IDLE:       _state_idle()
		State.PATROL:     _state_patrol(delta)
		State.CHASE:      _state_chase()
		State.ATTACK:     _state_attack()
		State.UNSTUCK:    _state_unstuck(delta)
		State.SEARCH:     _state_search(delta)
		State.RETREAT:    _state_retreat(delta)
		State.STRAFE:     _state_strafe(delta)
		State.SEEK_COVER: _state_seek_cover(delta)
		State.LISTEN:     _state_listen(delta)
		State.DEAD:       _state_dead()


func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	print("Enemy: State changed -> ", State.keys()[current_state], " to ", State.keys()[new_state])
	if current_state == State.UNSTUCK:
		visual.rotation.x = 0.0
		visual.rotation.z = 0.0
	time_in_state = 0.0
	current_state = new_state

	match new_state:
		State.RETREAT:
			retreat_timer = 0.0
		State.STRAFE:
			strafe_timer = 0.0
			strafe_direction = 1.0 if randf() > 0.5 else -1.0
		State.SEEK_COVER:
			cover_timer = 0.0
			cover_found = false
			cover_target = _find_cover_point()
			print("Enemy: Cover point found at -> ", cover_target)
		State.LISTEN:
			listen_timer = 0.0
		State.SEARCH:
			_reset_search()


func _state_idle() -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	play_animation(ANIM_IDLE)


func _state_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		return

	if is_waiting_at_point:
		patrol_wait_timer -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		play_animation(ANIM_IDLE)
		if patrol_wait_timer <= 0:
			is_waiting_at_point = false
			current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
			print("Enemy: Moving to patrol point ", current_patrol_index)
		return

	var target    = patrol_points[current_patrol_index]
	navigation_agent.target_position = target
	var next_pos  = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * (speed * 0.6)
	look_at(Vector3(target.x, global_position.y, target.z))
	move_and_slide()
	play_animation(ANIM_WALK)

	if global_position.distance_to(target) < 1.0:
		print("Enemy: Reached patrol point ", current_patrol_index, " waiting...")
		is_waiting_at_point = true
		patrol_wait_timer = patrol_wait_time


func _state_chase() -> void:
	navigation_agent.target_position = player.global_position
	var next_pos  = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	play_animation(ANIM_RUN)


func _state_attack() -> void:
	velocity = Vector3.ZERO
	is_attacking = true
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	if animation_player.current_animation != ANIM_ATTACK:
		animation_player.speed_scale = 1.8
		animation_player.play(ANIM_ATTACK, 0.1)


func _state_unstuck(delta: float) -> void:
	unstuck_timer += delta

	var to_player   = (player.global_position - global_position).normalized()
	var sideways    = to_player.cross(Vector3.UP).normalized() * unstuck_side
	var unstuck_dir = (to_player + sideways).normalized()

	velocity = unstuck_dir * speed
	var look_target  = global_position + unstuck_dir
	var target_xform = global_transform.looking_at(
		Vector3(look_target.x, global_position.y, look_target.z),
		Vector3.UP
	)
	global_transform.basis = global_transform.basis.slerp(target_xform.basis, delta * 8.0)
	move_and_slide()
	play_animation(ANIM_RUN)

	print("Enemy: Walking around obstacle... ", snappedf(unstuck_timer, 0.1), "s / ", unstuck_duration, "s")
	if unstuck_timer >= unstuck_duration:
		unstuck_timer = 0.0
		unstuck_side *= -1.0
		print("Enemy: Found new path, retrying chase!")
		_change_state(State.CHASE)


func _state_search(delta: float) -> void:
	search_timer += delta
	if search_timer >= search_duration:
		print("Enemy: Gave up searching, going back to patrol")
		_add_memory("SEARCH expired without finding player, reverting to PATROL")
		_change_state(State.PATROL)
		return

	if search_is_walking:
		search_walk_timer += delta
		velocity = search_direction * (speed * 0.5)
		var look_target = global_position + search_direction
		look_at(Vector3(look_target.x, global_position.y, look_target.z))
		move_and_slide()
		play_animation(ANIM_WALK)
		if search_walk_timer >= search_walk_duration:
			print("Enemy: Stopping to look around...")
			search_is_walking = false
			search_walk_timer = 0.0
			search_look_timer = 0.0
	else:
		search_look_timer += delta
		velocity = Vector3.ZERO
		move_and_slide()
		play_animation(ANIM_IDLE)
		rotate_y(delta * 1.2)
		if search_look_timer >= search_look_duration:
			print("Enemy: Done looking, walking again...")
			search_is_walking = true
			search_walk_timer = 0.0
			var base_dir     = (last_known_player_pos - global_position).normalized()
			search_direction = base_dir.rotated(Vector3.UP, deg_to_rad(randf_range(-45.0, 45.0)))


# ---------------------------------------------------------------------------
# RETREAT — back away while facing the player
# ---------------------------------------------------------------------------

func _state_retreat(delta: float) -> void:
	retreat_timer += delta

	var away = (global_position - player.global_position).normalized()
	away.y = 0
	navigation_agent.target_position = global_position + away * 5.0
	var next_pos  = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * (speed * 0.7)
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	play_animation(ANIM_WALK)

	print("Enemy: Retreating... ", snappedf(retreat_timer, 0.1), "s / ", retreat_duration, "s")
	if retreat_timer >= retreat_duration:
		retreat_timer = 0.0
		_add_memory("Finished retreating, distance to player now %.1f" % global_position.distance_to(player.global_position))
		_change_state(State.IDLE)


# ---------------------------------------------------------------------------
# STRAFE — circle around the player
# ---------------------------------------------------------------------------

func _state_strafe(delta: float) -> void:
	strafe_timer += delta

	var to_player = (player.global_position - global_position).normalized()
	to_player.y = 0
	var sideways  = to_player.cross(Vector3.UP).normalized() * strafe_direction
	var dir       = (sideways + to_player * 0.3).normalized()

	velocity = dir * speed
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z))
	move_and_slide()
	play_animation(ANIM_RUN)

	print("Enemy: Strafing... ", snappedf(strafe_timer, 0.1), "s / ", strafe_duration, "s")
	if strafe_timer >= strafe_duration:
		strafe_timer = 0.0
		_add_memory("Finished strafing around player")
		_change_state(State.CHASE)


# ---------------------------------------------------------------------------
# SEEK_COVER — navigate toward best nearby cover point
# ---------------------------------------------------------------------------

func _state_seek_cover(delta: float) -> void:
	cover_timer += delta

	navigation_agent.target_position = cover_target
	var next_pos  = navigation_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	look_at(Vector3((global_position + direction).x, global_position.y, (global_position + direction).z))
	move_and_slide()
	play_animation(ANIM_RUN)

	var dist = global_position.distance_to(cover_target)
	print("Enemy: Seeking cover... dist=", snappedf(dist, 0.1), " timer=", snappedf(cover_timer, 0.1))

	if dist < 1.0:
		print("Enemy: Reached cover!")
		_add_memory("Reached cover, distance to player now %.1f" % global_position.distance_to(player.global_position))
		_change_state(State.IDLE)
	elif cover_timer >= cover_duration:
		print("Enemy: Could not reach cover in time")
		_add_memory("Failed to reach cover in %.1fs, reverting to CHASE" % cover_duration)
		_change_state(State.CHASE)


# ---------------------------------------------------------------------------
# LISTEN — stand still, detect player by sound proximity
# ---------------------------------------------------------------------------

func _state_listen(delta: float) -> void:
	listen_timer += delta
	velocity = Vector3.ZERO
	move_and_slide()
	play_animation(ANIM_IDLE)
	rotate_y(delta * 0.5)

	var distance     = global_position.distance_to(player.global_position)
	var player_moving = player.velocity.length() > 0.5
	var heard        = distance < chase_range * 0.6 and player_moving and not can_see_player

	print("Enemy: Listening... dist=", snappedf(distance, 0.1), " heard=", heard)

	if heard:
		print("Enemy: Heard the player!")
		last_known_player_pos = player.global_position
		_add_memory("Heard player at distance %.1f while LISTENING, switching to SEARCH" % distance)
		_change_state(State.SEARCH)
		return

	if can_see_player:
		print("Enemy: Spotted player while listening!")
		_add_memory("Spotted player during LISTEN, switching to CHASE")
		_change_state(State.CHASE)
		return

	if listen_timer >= listen_duration:
		print("Enemy: Heard nothing, giving up")
		_add_memory("Listened for %.1fs, detected nothing, reverting to PATROL" % listen_duration)
		_change_state(State.PATROL)


func _state_dead() -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	play_animation(ANIM_DEAD)


# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	print("Enemy: Took ", amount, " damage! Health -> ", health - amount)
	health -= amount
	_add_memory("Took %.0f damage, health now %.0f%%" % [amount, (health / max_health) * 100.0])
	play_animation(ANIM_HIT)
	if health <= 0:
		print("Enemy: DEAD!")
		_add_memory("Died")
		_change_state(State.DEAD)


# ---------------------------------------------------------------------------
# Animation helper
# ---------------------------------------------------------------------------

func play_animation(anim_name: String) -> void:
	if anim_name != ANIM_ATTACK:
		animation_player.speed_scale = 1.0
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, 0.2)
