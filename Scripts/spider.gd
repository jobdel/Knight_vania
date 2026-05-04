extends EnemyBase

# --------------------
# State Machine
# --------------------
enum State { PATROL, CHASE, LUNGE, HURT, DEAD }
var state : State = State.PATROL

# --------------------
# Stats
# --------------------
const GRAVITY := 900.0
const PATROL_SPEED := 30.0
const CHASE_SPEED := 65.0
const LUNGE_FORCE := Vector2(120, -160)
const PATROL_DISTANCE := 60.0
const ATTACK_RANGE := 30.0

# Patrol
var spawn_x := 0.0
var patrol_dir := 1
var patrol_wait := 0.0

# Lunge cooldown
var lunge_cooldown := 0.0
const LUNGE_COOLDOWN := 1.2

# --------------------
# Nodes
# --------------------
var contact_area: Area2D
var contact_shape: CollisionShape2D

# Frame data for atlas textures
const IDLE_SHEET := "res://Assets/sprites/craft pix/Enemies/Spider_Idle.png"
const RUN_SHEET := "res://Assets/sprites/craft pix/Enemies/Spider_Run.png"
const JUMP_SHEET := "res://Assets/sprites/craft pix/Enemies/Spider_Jump.png"
const DEATH_SHEET := "res://Assets/sprites/craft pix/Enemies/Spider_Death.png"


func _ready():
	max_health = 2
	knockback_force = Vector2(70, -90)
	aggro_memory = 2.5
	contact_damage = 1

	init_enemy()

	spawn_x = global_position.x
	sprite.scale = Vector2(0.45, 0.45)

	_setup_sprite_frames()
	_setup_contact_area()
	setup_aggro_area(90.0)
	setup_edge_detector(8.0, 20.0)
	setup_health_bar(Vector2(20, 2), Vector2(-10, -18))
	play_anim("idle")


func _setup_sprite_frames():
	var frames := SpriteFrames.new()

	add_sheet_anim(frames, "idle", IDLE_SHEET, 4, 59, 56, 8.0, true)
	add_sheet_anim(frames, "run", RUN_SHEET, 5, 54, 40, 10.0, true)
	add_sheet_anim(frames, "jump", JUMP_SHEET, 5, 58, 44, 10.0, false)
	add_sheet_anim(frames, "death", DEATH_SHEET, 4, 57, 35, 8.0, false)

	if frames.has_animation("default"):
		frames.remove_animation("default")

	sprite.sprite_frames = frames


func _setup_contact_area():
	contact_area = Area2D.new()
	contact_area.collision_layer = 0
	contact_area.collision_mask = 2
	contact_area.monitoring = true

	contact_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	contact_shape.shape = shape
	contact_shape.position = Vector2(0, -4)

	contact_area.add_child(contact_shape)
	add_child(contact_area)


# --------------------
# Detection overrides
# --------------------
func _on_player_spotted():
	if state == State.PATROL:
		state = State.CHASE


func _is_dead() -> bool:
	return state == State.DEAD


# --------------------
# Physics
# --------------------
func _physics_process(delta: float):
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if aggro_timer > 0.0 and aggro_timer - get_physics_process_delta_time() <= 0.0:
		if not is_instance_valid(player):
			player = null
	if lunge_cooldown > 0.0:
		lunge_cooldown -= delta

	update_enemy_commons(delta)
	update_edge_ray_facing()

	match state:
		State.HURT:
			move_and_check_player()
			if is_on_floor() and velocity.y >= 0.0:
				if has_target():
					state = State.CHASE
				else:
					_enter_patrol()
			return
		State.LUNGE:
			_check_contact()
			move_and_check_player()
			if is_on_floor() and velocity.y >= 0.0:
				if has_target():
					state = State.CHASE
				else:
					_enter_patrol()
			return
		State.CHASE:
			_state_chase(delta)
		State.PATROL:
			_state_patrol(delta)

	move_and_check_player()
	_check_contact()
	_update_animation()


# --------------------
# Patrol
# --------------------
func _state_patrol(delta: float):
	if has_target():
		state = State.CHASE
		return

	if patrol_wait > 0.0:
		patrol_wait -= delta
		velocity.x = 0.0
		return

	var offset : float = global_position.x - spawn_x
	if offset >= PATROL_DISTANCE:
		patrol_dir = -1
		patrol_wait = 1.0 + randf() * 0.5
		velocity.x = 0.0
		return
	elif offset <= -PATROL_DISTANCE:
		patrol_dir = 1
		patrol_wait = 1.0 + randf() * 0.5
		velocity.x = 0.0
		return

	if is_on_floor() and not edge_ray.is_colliding():
		patrol_dir = -patrol_dir
		patrol_wait = 0.6 + randf() * 0.3
		velocity.x = 0.0
		return

	velocity.x = float(patrol_dir) * PATROL_SPEED
	face_dir(patrol_dir)


# --------------------
# Chase
# --------------------
func _state_chase(delta: float):
	if not has_target():
		_enter_patrol()
		return

	var target_pos := player.global_position if is_instance_valid(player) else Vector2(spawn_x, global_position.y)
	var diff : float = target_pos.x - global_position.x
	var dist : float = absf(diff)
	var dir : int = safe_dir(diff)

	face_dir(dir)

	if dist <= ATTACK_RANGE and is_on_floor() and lunge_cooldown <= 0.0:
		_lunge(dir)
		return

	if is_on_floor() and not edge_ray.is_colliding():
		velocity.x = 0.0
		return

	velocity.x = float(dir) * CHASE_SPEED


func _lunge(dir: int):
	state = State.LUNGE
	lunge_cooldown = LUNGE_COOLDOWN
	velocity = Vector2(float(dir) * LUNGE_FORCE.x, LUNGE_FORCE.y)
	play_anim("jump")


func _enter_patrol():
	state = State.PATROL
	player = null
	aggro_timer = 0.0


# --------------------
# Contact damage
# --------------------
func _check_contact():
	if state == State.DEAD:
		return
	for body in contact_area.get_overlapping_bodies():
		if body.is_in_group("Player") and body.has_method("take_damage"):
			body.take_damage(contact_damage, global_position, self)
			return


# --------------------
# Damage & Death
# --------------------
func _on_hurt():
	state = State.HURT
	apply_knockback()


func _on_die():
	state = State.DEAD
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	contact_shape.set_deferred("disabled", true)

	play_anim("death")
	await sprite.animation_finished
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


# --------------------
# Animations
# --------------------
func _update_animation():
	if state in [State.DEAD, State.LUNGE, State.HURT]:
		return
	if not is_on_floor():
		play_anim("jump")
	elif absf(velocity.x) > 1.0:
		play_anim("run")
	else:
		play_anim("idle")
