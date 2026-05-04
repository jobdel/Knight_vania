extends EnemyBase

# ═══════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════

enum State { PATROL, ALERT, CHASE, ATTACK, BOMB, HURT, DEAD }
var state : State = State.PATROL

# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

# Movement
const GRAVITY := 900.0
const PATROL_SPEED := 60.0
const CHASE_SPEED := 150.0
const ACCEL := 1000.0
const DECEL := 1400.0
const JUMP_FORCE := -320.0
const JUMP_COOLDOWN := 0.6

# Combat
const ATTACK_RANGE := 30.0
const BOMB_RANGE_MIN := 50.0
const BOMB_RANGE_MAX := 120.0
const ATTACK_COOLDOWN := 0.4
const BOMB_COOLDOWN := 2.0

# Patrol
const PATROL_DISTANCE := 70.0
const PATROL_PAUSE_MIN := 0.5
const PATROL_PAUSE_MAX := 1.2

# Detection & aggro
const ALERT_TIME := 0.2
const LEASH_RANGE := 200.0
const SEARCH_TIME := 1.0

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
var bomb_cooldown_timer := 0.0
var current_attack := 0
var attack_hit_bodies : Array = []

# Jump
var jump_cooldown_timer := 0.0

# ═══════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════

var attack_hitbox: Area2D
var hitbox_shape: CollisionShape2D


# ═══════════════════════════════════════════
#  READY & SETUP
# ═══════════════════════════════════════════

func _ready():
	max_health = 3
	knockback_force = Vector2(90, -80)
	aggro_memory = 3.0
	contact_damage = 1
	attack_damage = 1

	init_enemy()

	spawn_x = global_position.x

	setup_anim_config(["Attack", "Attack2", "BombToss", "Hit", "Death"], 2.0)

	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	_setup_attack_hitbox()
	setup_aggro_area(100.0)
	setup_edge_detector(12.0, 25.0)
	setup_health_bar(Vector2(28, 3), Vector2(-14, -45))

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
	shape.height = 28.0
	hitbox_shape.shape = shape
	hitbox_shape.position = Vector2(20, -20)
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


# ═══════════════════════════════════════════
#  PHYSICS MAIN
# ═══════════════════════════════════════════

func _physics_process(delta: float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if bomb_cooldown_timer > 0.0:
		bomb_cooldown_timer -= delta
	if jump_cooldown_timer > 0.0:
		jump_cooldown_timer -= delta

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
		State.BOMB:
			velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
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

	# Bomb toss at range
	if dist >= BOMB_RANGE_MIN and dist <= BOMB_RANGE_MAX and is_instance_valid(player) \
			and bomb_cooldown_timer <= 0.0 and is_on_floor():
		_start_bomb()
		return

	# Melee attack when close
	if dist <= ATTACK_RANGE and is_instance_valid(player) and attack_cooldown_timer <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		_start_attack()
		return

	# Jump if player is above or at an edge
	if is_on_floor() and jump_cooldown_timer <= 0.0:
		var should_jump := false
		if is_instance_valid(player) and player.global_position.y < global_position.y - 30.0:
			should_jump = true
		if not edge_ray.is_colliding() and dist > 20.0:
			should_jump = true
		if should_jump:
			velocity.y = JUMP_FORCE
			jump_cooldown_timer = JUMP_COOLDOWN

	if is_on_floor() and not edge_ray.is_colliding() and velocity.y >= 0.0:
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
#  STATE: ATTACK (melee)
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
#  STATE: BOMB (ranged attack)
# ═══════════════════════════════════════════

func _start_bomb():
	state = State.BOMB
	velocity.x = 0.0
	bomb_cooldown_timer = BOMB_COOLDOWN
	play_anim("BombToss")


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
	if state in [State.DEAD, State.ATTACK, State.BOMB, State.HURT]:
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
	elif state == State.BOMB:
		var f : int = sprite.frame
		if f == 7:
			_spawn_bomb()


func _on_animation_finished():
	match sprite.animation:
		"Attack", "Attack2":
			hitbox_shape.disabled = true
			attack_hit_bodies.clear()
			resume_after_action()
		"BombToss":
			_bomb_spawned_this_toss = false
			resume_after_action()
		"Hit":
			resume_after_action()


# ═══════════════════════════════════════════
#  BOMB PROJECTILE
# ═══════════════════════════════════════════

var _bomb_spawned_this_toss := false

func _spawn_bomb():
	if _bomb_spawned_this_toss:
		return
	_bomb_spawned_this_toss = true

	if not is_instance_valid(player):
		return

	var bomb := _GoblinBomb.new()
	bomb.source = self
	bomb.damage = attack_damage

	var facing : float = -1.0 if sprite.flip_h else 1.0
	bomb.global_position = global_position + Vector2(facing * 12.0, -20.0)

	var target := player.global_position
	var diff := target - bomb.global_position
	bomb.vel = Vector2(diff.x * 1.8, -180.0)

	get_parent().add_child(bomb)


class _GoblinBomb extends Area2D:
	const BOMB_SHEET := "res://Assets/sprites/Mobs/Monsters_Creatures_Fantasy/Monster_Creatures_Fantasy(Version 1.3)/Goblin/Bomb_sprite.png"
	const BOUNCE_DAMPING := 0.6
	const BOMB_GRAVITY := 500.0
	const FUSE_TIME := 3.0
	var vel := Vector2.ZERO
	var damage := 1
	var source: Node2D
	var has_hit := false
	var exploding := false
	var fuse_timer := FUSE_TIME
	var bomb_sprite: AnimatedSprite2D
	var floor_ray: RayCast2D

	func _ready():
		collision_layer = 0
		collision_mask = 2
		monitoring = true

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		col.shape = circle
		add_child(col)

		floor_ray = RayCast2D.new()
		floor_ray.target_position = Vector2(0, 8)
		floor_ray.collision_mask = 3
		floor_ray.enabled = true
		add_child(floor_ray)

		var sheet : Texture2D = load(BOMB_SHEET)
		var frames := SpriteFrames.new()

		frames.add_animation("fuse")
		frames.set_animation_speed("fuse", 6.0)
		frames.set_animation_loop("fuse", true)
		for i in range(3):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 100.0, 0, 100, 100)
			frames.add_frame("fuse", tex)

		frames.add_animation("explode")
		frames.set_animation_speed("explode", 16.0)
		frames.set_animation_loop("explode", false)
		for i in range(3, 19):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 100.0, 0, 100, 100)
			var dur := 0.5 if i >= 10 else 1.0
			frames.add_frame("explode", tex, dur)

		bomb_sprite = AnimatedSprite2D.new()
		bomb_sprite.sprite_frames = frames
		bomb_sprite.play("fuse")
		add_child(bomb_sprite)

		bomb_sprite.animation_finished.connect(_on_anim_done)
		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float):
		if exploding:
			return

		fuse_timer -= delta
		if fuse_timer <= 0.0:
			_start_explode()
			return

		vel.y += BOMB_GRAVITY * delta
		position += vel * delta

		if floor_ray.is_colliding() and vel.y > 0.0:
			vel.y = -absf(vel.y) * BOUNCE_DAMPING
			vel.x *= 0.8
			var col_point := floor_ray.get_collision_point()
			position.y = col_point.y - 4.0

	func _start_explode():
		if exploding:
			return
		exploding = true
		vel = Vector2.ZERO
		set_deferred("monitoring", false)
		bomb_sprite.play("explode")

	func _on_body_entered(body: Node2D):
		if has_hit:
			return
		if body.is_in_group("Player") and body.has_method("take_damage"):
			has_hit = true
			body.take_damage(damage, global_position, source)
			_start_explode()

	func _on_anim_done():
		if bomb_sprite.animation == "explode":
			queue_free()


# ═══════════════════════════════════════════
#  DAMAGE & DEATH
# ═══════════════════════════════════════════

func _on_hurt():
	state = State.HURT
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	_bomb_spawned_this_toss = false
	apply_knockback()
	play_anim("Hit")


func _on_die():
	state = State.DEAD
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	velocity = Vector2.ZERO
	die_with_fadeout()
