extends EnemyBase

# --------------------
# State Machine
# --------------------
enum State { PATROL, CHASE, HURT, DEAD }
var state : State = State.PATROL

# --------------------
# Stats
# --------------------
const GRAVITY := 900.0
const JUMP_FORCE := -180.0
const HOP_SPEED := 45.0
const CHASE_HOP_SPEED := 80.0
const CHASE_JUMP_FORCE := -200.0
const PATROL_DISTANCE := 80.0
const STOMP_BOUNCE := -250.0
const HOP_INTERVAL := 1.8
const CHASE_HOP_INTERVAL := 0.8

# Patrol
var spawn_x := 0.0
var patrol_dir := 1
var hop_timer := 0.0
var hop_count := 0
var big_hop_interval := 3

# Landing squish
var was_airborne := false

# --------------------
# Nodes
# --------------------
var player_detect: Area2D
var detect_shape: CollisionShape2D


func _ready():
	max_health = 2
	knockback_force = Vector2(60, -100)
	aggro_memory = 2.5
	contact_damage = 1

	init_enemy()

	spawn_x = global_position.x
	big_hop_interval = 3 + randi() % 2

	sprite.sprite_frames.set_animation_loop("death", false)

	_setup_player_detection()
	setup_aggro_area(120.0, Vector2(0, -8))
	setup_edge_detector(10.0, 20.0)
	setup_health_bar(Vector2(20, 2), Vector2(-10, -26))
	play_anim("idle")


func _setup_player_detection():
	player_detect = Area2D.new()
	player_detect.collision_layer = 0
	player_detect.collision_mask = 2
	player_detect.monitoring = true

	detect_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	detect_shape.shape = shape
	detect_shape.position = Vector2(0, -8)

	player_detect.add_child(detect_shape)
	add_child(player_detect)


# --------------------
# Detection overrides
# --------------------
func _on_player_spotted():
	if state == State.PATROL:
		state = State.CHASE


func _is_dead() -> bool:
	return state == State.DEAD


func _enter_combat_state():
	state = State.CHASE


func _enter_idle_state():
	_enter_patrol()


# --------------------
# Physics
# --------------------
func _physics_process(delta: float):
	if state == State.DEAD:
		if not is_on_floor():
			velocity.y += GRAVITY * delta
			move_and_check_player()
		return

	update_enemy_commons(delta)

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		was_airborne = true
	else:
		if was_airborne:
			was_airborne = false
			_land_squish()

	match state:
		State.HURT:
			move_and_check_player()
			if is_on_floor() and velocity.y >= 0.0:
				resume_after_action()
			return
		State.CHASE:
			_state_chase(delta)
		State.PATROL:
			_state_patrol(delta)

	move_and_check_player()
	_check_player_contact()
	_update_animation()


# --------------------
# State: PATROL
# --------------------
func _state_patrol(delta: float):
	if has_target():
		state = State.CHASE
		return

	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		hop_timer -= delta
		if hop_timer <= 0.0:
			_hop_patrol()


func _hop_patrol():
	update_edge_ray_facing()
	if not edge_ray.is_colliding():
		patrol_dir = -patrol_dir
		update_edge_ray_facing()

	var offset : float = global_position.x - spawn_x
	if offset >= PATROL_DISTANCE:
		patrol_dir = -1
	elif offset <= -PATROL_DISTANCE:
		patrol_dir = 1

	hop_count += 1
	var is_big := hop_count % big_hop_interval == 0
	hop_timer = HOP_INTERVAL + randf() * 0.6
	velocity.y = JUMP_FORCE * (2.0 if is_big else 1.0)
	velocity.x = float(patrol_dir) * HOP_SPEED
	sprite.flip_h = patrol_dir < 0


# --------------------
# State: CHASE
# --------------------
func _state_chase(delta: float):
	if not has_target():
		_enter_patrol()
		return

	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
		hop_timer -= delta
		if hop_timer <= 0.0:
			_hop_chase()


func _hop_chase():
	update_edge_ray_facing()
	if not edge_ray.is_colliding():
		patrol_dir = -patrol_dir
		update_edge_ray_facing()
		hop_timer = CHASE_HOP_INTERVAL
		return

	if is_instance_valid(player):
		var diff : float = player.global_position.x - global_position.x
		var dir : int = safe_dir(diff)
		patrol_dir = dir

	hop_count += 1
	var is_big := hop_count % big_hop_interval == 0
	hop_timer = CHASE_HOP_INTERVAL + randf() * 0.3
	velocity.y = CHASE_JUMP_FORCE * (2.0 if is_big else 1.0)
	velocity.x = float(patrol_dir) * CHASE_HOP_SPEED
	sprite.flip_h = patrol_dir < 0


func _enter_patrol():
	state = State.PATROL
	player = null
	aggro_timer = 0.0


# --------------------
# Helpers
# --------------------
func _land_squish():
	if state == State.DEAD:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.3, 0.7), 0.08)
	tween.tween_property(sprite, "scale", Vector2(0.9, 1.1), 0.06)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.06)


# --------------------
# Player Contact
# --------------------
func _check_player_contact():
	if state == State.DEAD:
		return
	for body in player_detect.get_overlapping_bodies():
		if not body.is_in_group("Player"):
			continue
		if _is_stomp(body):
			_stomped(body)
		elif body.has_method("take_damage"):
			body.take_damage(contact_damage, global_position, self)
		return


func _is_stomp(body: Node2D) -> bool:
	if not body is CharacterBody2D:
		return false
	return body.velocity.y > 0.0 and body.global_position.y < global_position.y - 4.0


func _stomped(player_body: Node2D):
	if player_body is CharacterBody2D:
		(player_body as CharacterBody2D).velocity.y = STOMP_BOUNCE

	_on_die()

	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.5, 0.2), 0.15)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)


# --------------------
# Damage & Death
# --------------------
func _on_hurt():
	state = State.HURT
	apply_knockback()


func _on_die():
	state = State.DEAD
	collision_layer = 0
	collision_mask = 1
	detect_shape.set_deferred("disabled", true)
	play_anim("death")
	await sprite.animation_finished
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _update_animation():
	if state == State.DEAD:
		return
	if not is_on_floor():
		play_anim("jump")
	else:
		play_anim("idle")
