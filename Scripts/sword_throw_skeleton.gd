extends EnemyBase

# ═══════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════

enum State { PATROL, ALERT, CHASE, ATTACK, THROW, BLOCK, HURT, DEAD }
var state : State = State.PATROL

# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

# Movement
const GRAVITY := 900.0
const PATROL_SPEED := 25.0
const CHASE_SPEED := 60.0
const ACCEL := 500.0
const DECEL := 700.0

# Combat
const ATTACK_RANGE := 32.0
const THROW_RANGE_MIN := 55.0
const THROW_RANGE_MAX := 160.0
const ATTACK_COOLDOWN := 0.9
const THROW_COOLDOWN := 3.0
const BLOCK_DURATION := 0.8
const BLOCK_CHANCE := 0.4

# Patrol
const PATROL_DISTANCE := 65.0
const PATROL_PAUSE_MIN := 1.2
const PATROL_PAUSE_MAX := 3.0

# Detection & aggro
const ALERT_TIME := 0.4
const LEASH_RANGE := 210.0
const SEARCH_TIME := 2.5

# ═══════════════════════════════════════════
#  STATE VARIABLES
# ═══════════════════════════════════════════

# Patrol
var spawn_x := 0.0
var patrol_dir := 1
var patrol_timer := 0.0
var patrol_paused := false

# Alert
var alert_timer := 0.0

# Search
var search_timer := 0.0

# Attack
var attack_cooldown_timer := 0.0
var throw_cooldown_timer := 0.0
var current_attack := 0
var attack_hit_bodies : Array = []

# Block
var block_timer := 0.0
var is_blocking := false

# Sword throw guard
var _sword_spawned_this_throw := false

# ═══════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════

var attack_hitbox: Area2D
var hitbox_shape: CollisionShape2D


# ═══════════════════════════════════════════
#  READY & SETUP
# ═══════════════════════════════════════════

func _ready():
	max_health = 4
	knockback_force = Vector2(80, -70)
	aggro_memory = 3.5
	contact_damage = 1
	attack_damage = 1

	init_enemy()

	spawn_x = global_position.x

	setup_anim_config(["Attack", "Attack2", "SwordThrow", "Hit", "Death", "Block"])

	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	_setup_attack_hitbox()
	setup_aggro_area(110.0)
	setup_edge_detector(12.0, 25.0)
	setup_health_bar(Vector2(30, 3), Vector2(-15, -55))

	patrol_dir = 1 if randf() > 0.5 else -1
	patrol_timer = randf() * PATROL_PAUSE_MAX
	patrol_paused = true
	face_dir(patrol_dir)
	play_anim("Idle")


func _setup_attack_hitbox():
	attack_hitbox = Area2D.new()
	attack_hitbox.collision_layer = 0
	attack_hitbox.collision_mask = 2
	attack_hitbox.monitoring = true

	hitbox_shape = CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 8.0
	shape.height = 30.0
	hitbox_shape.shape = shape
	hitbox_shape.position = Vector2(22, -25)
	hitbox_shape.rotation = PI / 2.0
	hitbox_shape.disabled = true

	attack_hitbox.add_child(hitbox_shape)
	add_child(attack_hitbox)


# ═══════════════════════════════════════════
#  DETECTION OVERRIDES
# ═══════════════════════════════════════════

func _on_player_spotted():
	if state == State.PATROL:
		_enter_alert()


func _on_player_lost():
	last_known_player_pos = player.global_position


func _is_dead() -> bool:
	return state == State.DEAD


func _enter_combat_state():
	_enter_chase()


func _enter_idle_state():
	_enter_patrol()


## Shield block: chance to block if in chase state
func _on_damage_blocked(_amount: int) -> bool:
	if state == State.CHASE and not is_blocking and randf() < BLOCK_CHANCE:
		_start_block()
		flash_timer = FLASH_DURATION
		return true
	if is_blocking:
		flash_timer = FLASH_DURATION
		return true
	return false


# ═══════════════════════════════════════════
#  PHYSICS MAIN
# ═══════════════════════════════════════════

func _physics_process(delta: float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if throw_cooldown_timer > 0.0:
		throw_cooldown_timer -= delta

	update_enemy_commons(delta)
	_update_rays()

	match state:
		State.DEAD:
			return
		State.HURT:
			move_and_check_player()
			if is_on_floor() and velocity.y >= 0.0:
				resume_after_action()
			return
		State.ATTACK:
			_process_attack_hits()
			move_and_check_player()
			return
		State.THROW:
			velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
			move_and_check_player()
			return
		State.BLOCK:
			velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
			block_timer -= delta
			if block_timer <= 0.0:
				is_blocking = false
				resume_after_action()
			move_and_check_player()
			return
		State.ALERT:
			_state_alert(delta)
		State.CHASE:
			_state_chase(delta)
		State.PATROL:
			_state_patrol(delta)

	move_and_check_player()
	_update_animation()


# ═══════════════════════════════════════════
#  STATE: PATROL
# ═══════════════════════════════════════════

func _state_patrol(delta: float):
	if has_target():
		_enter_alert()
		return

	if patrol_paused:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		patrol_timer -= delta
		if patrol_timer <= 0.0:
			patrol_paused = false
			var offset : float = global_position.x - spawn_x
			if (patrol_dir == 1 and offset >= PATROL_DISTANCE) or \
			   (patrol_dir == -1 and offset <= -PATROL_DISTANCE):
				patrol_dir = -patrol_dir
				face_dir(patrol_dir)
		return

	var offset : float = global_position.x - spawn_x
	if (patrol_dir == 1 and offset >= PATROL_DISTANCE) or \
	   (patrol_dir == -1 and offset <= -PATROL_DISTANCE):
		_patrol_pause()
		return

	if is_on_floor() and not edge_ray.is_colliding():
		_patrol_pause()
		return

	velocity.x = move_toward(velocity.x, float(patrol_dir) * PATROL_SPEED, ACCEL * delta)
	face_dir(patrol_dir)


func _patrol_pause():
	patrol_paused = true
	patrol_timer = PATROL_PAUSE_MIN + randf() * (PATROL_PAUSE_MAX - PATROL_PAUSE_MIN)
	velocity.x = 0.0


# ═══════════════════════════════════════════
#  STATE: ALERT
# ═══════════════════════════════════════════

func _enter_alert():
	state = State.ALERT
	alert_timer = ALERT_TIME
	velocity.x = 0.0
	if is_instance_valid(player):
		face_dir(safe_dir(player.global_position.x - global_position.x))


func _state_alert(delta: float):
	velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	alert_timer -= delta
	if alert_timer <= 0.0:
		_enter_chase()


# ═══════════════════════════════════════════
#  STATE: CHASE
# ═══════════════════════════════════════════

func _enter_chase():
	state = State.CHASE
	search_timer = 0.0


func _state_chase(delta: float):
	if not has_target() and aggro_timer <= 0.0:
		if search_timer <= 0.0:
			search_timer = SEARCH_TIME
		search_timer -= delta
		if search_timer <= 0.0:
			_enter_patrol()
			return

	if is_instance_valid(player):
		last_known_player_pos = player.global_position

	var dist_from_spawn := absf(global_position.x - spawn_x)
	if dist_from_spawn > LEASH_RANGE and not has_target():
		_enter_patrol()
		return

	var target_x : float
	if is_instance_valid(player):
		target_x = player.global_position.x
	else:
		target_x = last_known_player_pos.x

	var diff : float = target_x - global_position.x
	var dist : float = absf(diff)
	var dir : int = safe_dir(diff)

	face_dir(dir)

	# Sword throw at range
	if dist >= THROW_RANGE_MIN and dist <= THROW_RANGE_MAX and is_instance_valid(player) \
			and throw_cooldown_timer <= 0.0 and is_on_floor():
		_start_throw()
		return

	# Melee attack when close
	if dist <= ATTACK_RANGE and is_instance_valid(player) and attack_cooldown_timer <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		_start_attack()
		return

	if is_on_floor() and not edge_ray.is_colliding():
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		return

	velocity.x = move_toward(velocity.x, float(dir) * CHASE_SPEED, ACCEL * delta)


func _enter_patrol():
	state = State.PATROL
	player = null
	aggro_timer = 0.0
	search_timer = 0.0
	patrol_paused = true
	patrol_timer = PATROL_PAUSE_MIN
	velocity.x = 0.0


# ═══════════════════════════════════════════
#  STATE: ATTACK (melee sword slash)
# ═══════════════════════════════════════════

func _start_attack():
	state = State.ATTACK
	velocity.x = 0.0
	attack_cooldown_timer = ATTACK_COOLDOWN
	attack_hit_bodies.clear()
	hitbox_shape.disabled = true

	if current_attack == 0:
		play_anim("Attack")
	else:
		play_anim("Attack2")
	current_attack = (current_attack + 1) % 2


func _process_attack_hits():
	for body in attack_hitbox.get_overlapping_bodies():
		if body in attack_hit_bodies:
			continue
		if body.is_in_group("Player") and body.has_method("take_damage"):
			attack_hit_bodies.append(body)
			body.take_damage(attack_damage, global_position, self)


# ═══════════════════════════════════════════
#  STATE: THROW (ranged sword projectile)
# ═══════════════════════════════════════════

func _start_throw():
	state = State.THROW
	velocity.x = 0.0
	throw_cooldown_timer = THROW_COOLDOWN
	_sword_spawned_this_throw = false
	play_anim("SwordThrow")


func _spawn_sword():
	if _sword_spawned_this_throw:
		return
	_sword_spawned_this_throw = true

	if not is_instance_valid(player):
		return

	var sword := _ThrownSword.new()
	sword.source = self
	sword.damage = attack_damage

	var facing : float = -1.0 if sprite.flip_h else 1.0
	sword.global_position = global_position + Vector2(facing * 16.0, -28.0)

	var target := player.global_position
	var diff := target - sword.global_position
	var dir := diff.normalized()
	sword.vel = dir * 180.0

	get_parent().add_child(sword)


# ═══════════════════════════════════════════
#  STATE: BLOCK (shield raise)
# ═══════════════════════════════════════════

func _start_block():
	state = State.BLOCK
	velocity.x = 0.0
	block_timer = BLOCK_DURATION
	is_blocking = true
	play_anim("Block")


# ═══════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════

func _update_rays():
	update_edge_ray_facing()
	var facing : float = -1.0 if sprite.flip_h else 1.0
	hitbox_shape.position.x = facing * absf(hitbox_shape.position.x)


# ═══════════════════════════════════════════
#  ANIMATION
# ═══════════════════════════════════════════

func _update_animation():
	if state in [State.DEAD, State.ATTACK, State.THROW, State.BLOCK, State.HURT]:
		return
	if not is_on_floor():
		play_anim("Run")
	elif absf(velocity.x) > 5.0:
		play_anim("Run")
	else:
		play_anim("Idle")


func _on_frame_changed():
	if state == State.ATTACK:
		var f : int = sprite.frame
		if f >= 4 and f <= 6:
			hitbox_shape.disabled = false
		else:
			hitbox_shape.disabled = true
	elif state == State.THROW:
		if sprite.frame == 3:
			_spawn_sword()


func _on_animation_finished():
	match sprite.animation:
		"Attack", "Attack2":
			hitbox_shape.disabled = true
			attack_hit_bodies.clear()
			resume_after_action()
		"SwordThrow":
			_sword_spawned_this_throw = false
			resume_after_action()
		"Block":
			is_blocking = false
			resume_after_action()
		"Hit":
			resume_after_action()


# ═══════════════════════════════════════════
#  THROWN SWORD PROJECTILE
# ═══════════════════════════════════════════

class _ThrownSword extends Area2D:
	const SWORD_SHEET := "res://Assets/sprites/Mobs/Monsters_Creatures_Fantasy/Monster_Creatures_Fantasy(Version 1.3)/Skeleton/Sword_sprite.png"
	var vel := Vector2.ZERO
	var damage := 1
	var source: Node2D
	var has_hit := false
	var lifetime := 4.0
	var sword_sprite: AnimatedSprite2D

	func _ready():
		collision_layer = 0
		collision_mask = 2
		monitoring = true

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		col.shape = circle
		add_child(col)

		var sheet : Texture2D = load(SWORD_SHEET)
		var frames := SpriteFrames.new()

		frames.add_animation("spin")
		frames.set_animation_speed("spin", 16.0)
		frames.set_animation_loop("spin", true)
		for i in range(4):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 50.0, 0, 50, 50)
			frames.add_frame("spin", tex)

		frames.add_animation("hit")
		frames.set_animation_speed("hit", 12.0)
		frames.set_animation_loop("hit", false)
		for i in range(4, 8):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 50.0, 0, 50, 50)
			frames.add_frame("hit", tex)

		sword_sprite = AnimatedSprite2D.new()
		sword_sprite.sprite_frames = frames
		sword_sprite.play("spin")
		add_child(sword_sprite)

		sword_sprite.animation_finished.connect(_on_anim_done)
		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float):
		if has_hit:
			return
		position += vel * delta
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node2D):
		if has_hit:
			return
		if body.is_in_group("Player") and body.has_method("take_damage"):
			has_hit = true
			body.take_damage(damage, global_position, source)
			vel = Vector2.ZERO
			set_deferred("monitoring", false)
			sword_sprite.play("hit")

	func _on_anim_done():
		if sword_sprite.animation == "hit":
			queue_free()


# ═══════════════════════════════════════════
#  DAMAGE & DEATH
# ═══════════════════════════════════════════

func _on_hurt():
	state = State.HURT
	is_blocking = false
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	_sword_spawned_this_throw = false
	apply_knockback()
	play_anim("Hit")


func _on_die():
	state = State.DEAD
	is_blocking = false
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	velocity = Vector2.ZERO
	die_with_fadeout()
