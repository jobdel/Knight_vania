extends EnemyBase

# ═══════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════

enum State { HOVER, CHASE, DIVE, SHOOT, HURT, DEAD }
var state : State = State.HOVER

# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

# Movement
const HOVER_BOB_SPEED := 2.5
const HOVER_BOB_AMP := 8.0
const PATROL_SPEED := 25.0
const PATROL_DISTANCE := 60.0
const CHASE_SPEED := 70.0
const CHASE_ACCEL := 300.0
const HOVER_HEIGHT := -40.0

# Combat
const DIVE_SPEED := 180.0
const DIVE_RANGE := 45.0
const SHOOT_RANGE_MIN := 60.0
const SHOOT_RANGE_MAX := 140.0
const DIVE_COOLDOWN := 2.0
const SHOOT_COOLDOWN := 3.0

# Detection
const LEASH_RANGE := 220.0
const RETURN_SPEED := 50.0

# Hurt
const HURT_DURATION := 0.35

# ═══════════════════════════════════════════
#  STATE VARIABLES
# ═══════════════════════════════════════════

# Hover / patrol
var spawn_pos := Vector2.ZERO
var bob_time := 0.0
var patrol_dir := 1

# Combat timers
var dive_cooldown_timer := 0.0
var shoot_cooldown_timer := 0.0
var dive_target := Vector2.ZERO
var dive_hit := false

# Hurt
var hurt_timer := 0.0

# Projectile spawn guard
var _projectile_spawned := false

# ═══════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════

var contact_area: Area2D
var contact_shape: CollisionShape2D


# ═══════════════════════════════════════════
#  READY & SETUP
# ═══════════════════════════════════════════

func _ready():
	max_health = 2
	knockback_force = Vector2(70, -80)
	aggro_memory = 3.0
	contact_damage = 1
	attack_damage = 1

	init_enemy()

	spawn_pos = global_position

	setup_anim_config(["Attack1", "Attack2", "Attack3", "Hit", "Death"], 2.0)

	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	_setup_contact_area()
	setup_aggro_area(120.0)
	setup_health_bar(Vector2(24, 3), Vector2(-12, -35))

	patrol_dir = 1 if randf() > 0.5 else -1
	play_anim("Flight")


func _setup_contact_area():
	contact_area = Area2D.new()
	contact_area.collision_layer = 0
	contact_area.collision_mask = 2
	contact_area.monitoring = true

	contact_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	contact_shape.shape = shape

	contact_area.add_child(contact_shape)
	add_child(contact_area)


# ═══════════════════════════════════════════
#  DETECTION OVERRIDES
# ═══════════════════════════════════════════

func _on_player_spotted():
	if state == State.HOVER:
		state = State.CHASE


func _on_player_lost():
	last_known_player_pos = player.global_position


func _is_dead() -> bool:
	return state == State.DEAD


func _enter_combat_state():
	state = State.CHASE


func _enter_idle_state():
	_enter_return()


# ═══════════════════════════════════════════
#  PHYSICS MAIN
# ═══════════════════════════════════════════

func _physics_process(delta: float):
	if state == State.DEAD:
		return

	if dive_cooldown_timer > 0.0:
		dive_cooldown_timer -= delta
	if shoot_cooldown_timer > 0.0:
		shoot_cooldown_timer -= delta

	update_enemy_commons(delta)

	match state:
		State.HOVER:
			_state_hover(delta)
		State.CHASE:
			_state_chase(delta)
		State.DIVE:
			_state_dive(delta)
		State.SHOOT:
			pass  # waiting for animation
		State.HURT:
			_state_hurt(delta)

	global_position += velocity * delta
	_check_contact()


# ═══════════════════════════════════════════
#  STATE: HOVER (idle patrol)
# ═══════════════════════════════════════════

func _state_hover(delta: float):
	bob_time += delta

	var offset_x : float = global_position.x - spawn_pos.x
	if offset_x >= PATROL_DISTANCE:
		patrol_dir = -1
	elif offset_x <= -PATROL_DISTANCE:
		patrol_dir = 1

	velocity.x = float(patrol_dir) * PATROL_SPEED
	velocity.y = sin(bob_time * HOVER_BOB_SPEED) * HOVER_BOB_AMP * 4.0

	var height_diff : float = spawn_pos.y - global_position.y
	velocity.y += height_diff * 2.0 * delta

	sprite.flip_h = patrol_dir < 0

	if has_target():
		state = State.CHASE

	play_anim("Flight")


# ═══════════════════════════════════════════
#  STATE: CHASE
# ═══════════════════════════════════════════

func _state_chase(delta: float):
	if not has_target():
		_enter_return()
		return

	var dist_from_spawn : float = global_position.distance_to(spawn_pos)
	if dist_from_spawn > LEASH_RANGE and not is_instance_valid(player):
		_enter_return()
		return

	var target_pos := Vector2.ZERO
	if is_instance_valid(player):
		target_pos = player.global_position + Vector2(0, HOVER_HEIGHT)
		last_known_player_pos = player.global_position
	else:
		target_pos = last_known_player_pos + Vector2(0, HOVER_HEIGHT)

	var dir_vec := (target_pos - global_position)
	var dist : float = dir_vec.length()

	if dist > 4.0:
		var desired := dir_vec.normalized() * CHASE_SPEED
		velocity = velocity.move_toward(desired, CHASE_ACCEL * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, CHASE_ACCEL * delta)

	if is_instance_valid(player):
		sprite.flip_h = player.global_position.x < global_position.x

		var player_dist : float = global_position.distance_to(player.global_position)

		if player_dist <= DIVE_RANGE and dive_cooldown_timer <= 0.0:
			_start_dive()
			return

		if player_dist >= SHOOT_RANGE_MIN and player_dist <= SHOOT_RANGE_MAX \
				and shoot_cooldown_timer <= 0.0:
			_start_shoot()
			return

	play_anim("Flight")


func _enter_return():
	state = State.HOVER
	bob_time = 0.0
	var dir_vec := (spawn_pos - global_position)
	if dir_vec.length() > 4.0:
		velocity = dir_vec.normalized() * RETURN_SPEED
	else:
		velocity = Vector2.ZERO
		global_position = spawn_pos


# ═══════════════════════════════════════════
#  STATE: DIVE ATTACK
# ═══════════════════════════════════════════

func _start_dive():
	state = State.DIVE
	dive_cooldown_timer = DIVE_COOLDOWN
	dive_hit = false

	if is_instance_valid(player):
		dive_target = player.global_position
	else:
		dive_target = last_known_player_pos

	var dir : float = signf(dive_target.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	sprite.flip_h = dir < 0.0

	play_anim("Attack1")


func _state_dive(delta: float):
	var dir_vec := (dive_target - global_position).normalized()
	velocity = dir_vec * DIVE_SPEED

	if global_position.distance_to(dive_target) < 10.0:
		_end_dive()


func _end_dive():
	velocity = Vector2(velocity.x * 0.3, -60.0)
	if has_target():
		state = State.CHASE
	else:
		_enter_return()


# ═══════════════════════════════════════════
#  STATE: PROJECTILE ATTACK
# ═══════════════════════════════════════════

func _start_shoot():
	state = State.SHOOT
	shoot_cooldown_timer = SHOOT_COOLDOWN
	_projectile_spawned = false
	velocity = velocity * 0.2

	if is_instance_valid(player):
		sprite.flip_h = player.global_position.x < global_position.x

	play_anim("Attack3")


func _spawn_projectile():
	if _projectile_spawned:
		return
	_projectile_spawned = true

	if not is_instance_valid(player):
		return

	var proj := _EyeProjectile.new()
	proj.source = self
	proj.damage = attack_damage
	proj.sprite_frames_res = sprite.sprite_frames

	var facing : float = -1.0 if sprite.flip_h else 1.0
	proj.global_position = global_position + Vector2(facing * 15.0, 0.0)

	var dir := (player.global_position - proj.global_position).normalized()
	proj.vel = dir * 120.0

	get_parent().add_child(proj)


# ═══════════════════════════════════════════
#  CONTACT DAMAGE
# ═══════════════════════════════════════════

func _check_contact():
	if state == State.DEAD:
		return
	if state != State.DIVE:
		return
	if dive_hit:
		return
	for body in contact_area.get_overlapping_bodies():
		if body.is_in_group("Player") and body.has_method("take_damage"):
			dive_hit = true
			body.take_damage(attack_damage, global_position, self)
			_end_dive()
			return


# ═══════════════════════════════════════════
#  ANIMATION
# ═══════════════════════════════════════════

func _on_animation_finished():
	match sprite.animation:
		"Attack1":
			_end_dive()
		"Attack3":
			_projectile_spawned = false
			resume_after_action()
		"Hit":
			resume_after_action()
		"Death":
			var tween := create_tween()
			tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
			tween.tween_callback(queue_free)


func _on_frame_changed():
	if state == State.SHOOT:
		var f : int = sprite.frame
		if f == 3:
			_spawn_projectile()


# ═══════════════════════════════════════════
#  DAMAGE & DEATH
# ═══════════════════════════════════════════

func _on_hurt():
	state = State.HURT
	hurt_timer = HURT_DURATION
	_projectile_spawned = false
	apply_knockback()
	play_anim("Hit")


func _state_hurt(delta: float):
	velocity = velocity.move_toward(Vector2.ZERO, 150.0 * delta)
	hurt_timer -= delta
	if hurt_timer <= 0.0:
		resume_after_action()


func _on_die():
	state = State.DEAD
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	contact_shape.set_deferred("disabled", true)

	play_anim("Death")

	var tween := create_tween()
	tween.tween_property(self, "global_position:y", global_position.y + 50.0, 0.6) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# ═══════════════════════════════════════════
#  PROJECTILE INNER CLASS
# ═══════════════════════════════════════════

class _EyeProjectile extends Area2D:
	var vel := Vector2.ZERO
	var damage := 1
	var source: Node2D
	var has_hit := false
	var lifetime := 4.0
	var sprite_frames_res: SpriteFrames
	var proj_sprite: AnimatedSprite2D

	func _ready():
		collision_layer = 0
		collision_mask = 2
		monitoring = true

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		col.shape = circle
		add_child(col)

		proj_sprite = AnimatedSprite2D.new()
		if sprite_frames_res and sprite_frames_res.has_animation("Projectile"):
			proj_sprite.sprite_frames = sprite_frames_res
			proj_sprite.play("Projectile")
		add_child(proj_sprite)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float):
		position += vel * delta
		lifetime -= delta

		if vel.length() > 0.0:
			proj_sprite.rotation = vel.angle()

		if lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node2D):
		if has_hit:
			return
		if body.is_in_group("Player") and body.has_method("take_damage"):
			has_hit = true
			body.take_damage(damage, global_position, source)
			queue_free()
