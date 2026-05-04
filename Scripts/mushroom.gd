extends EnemyBase

# ═══════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════

enum State { PATROL, ALERT, CHASE, ATTACK, SPORE, HURT, DEAD }
var state : State = State.PATROL

# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

# Movement
const GRAVITY := 900.0
const PATROL_SPEED := 20.0
const CHASE_SPEED := 50.0
const ACCEL := 400.0
const DECEL := 600.0

# Combat
const ATTACK_RANGE := 28.0
const SPORE_RANGE_MIN := 45.0
const SPORE_RANGE_MAX := 140.0
const ATTACK_COOLDOWN := 1.0
const SPORE_COOLDOWN := 4.0

# Patrol
const PATROL_DISTANCE := 60.0
const PATROL_PAUSE_MIN := 1.5
const PATROL_PAUSE_MAX := 3.5

# Detection & aggro
const ALERT_TIME := 0.5
const LEASH_RANGE := 220.0
const SEARCH_TIME := 3.0

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
var spore_cooldown_timer := 0.0
var current_attack := 0
var attack_hit_bodies : Array = []

# Spore spawn guard
var _spore_spawned_this_toss := false

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
	knockback_force = Vector2(60, -60)
	aggro_memory = 4.0
	contact_damage = 1
	attack_damage = 1

	init_enemy()

	spawn_x = global_position.x

	setup_anim_config(["Attack", "Attack2", "ThrowProjectile", "Hit", "Death"])

	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	_setup_attack_hitbox()
	setup_aggro_area(120.0)
	setup_edge_detector(10.0, 25.0)
	setup_health_bar(Vector2(30, 3), Vector2(-15, -48))

	patrol_dir = 1 if randf() > 0.5 else -1
	patrol_timer = randf() * PATROL_PAUSE_MAX
	patrol_paused = true
	face_dir(patrol_dir)
	play_anim("Idle")


func _setup_attack_hitbox():
	# Disable any scene-placed hitbox (not used — we create our own)
	var scene_hitbox := get_node_or_null("HitboxAttack1&2")
	if scene_hitbox != null:
		scene_hitbox.set_deferred("disabled", true)

	attack_hitbox = Area2D.new()
	attack_hitbox.collision_layer = 0
	attack_hitbox.collision_mask = 2
	attack_hitbox.monitoring = true

	hitbox_shape = CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 12.0
	shape.height = 34.0
	hitbox_shape.shape = shape
	hitbox_shape.position = Vector2(23, -17)
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
	if spore_cooldown_timer > 0.0:
		spore_cooldown_timer -= delta

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
		State.SPORE:
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

	# Spore toss at range
	if dist >= SPORE_RANGE_MIN and dist <= SPORE_RANGE_MAX and is_instance_valid(player) \
			and spore_cooldown_timer <= 0.0 and is_on_floor():
		_start_spore()
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
#  STATE: ATTACK (melee headbutt)
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
#  STATE: SPORE (ranged — poison cloud)
# ═══════════════════════════════════════════

func _start_spore():
	state = State.SPORE
	velocity.x = 0.0
	spore_cooldown_timer = SPORE_COOLDOWN
	_spore_spawned_this_toss = false
	play_anim("ThrowProjectile")


func _spawn_spore():
	if _spore_spawned_this_toss:
		return
	_spore_spawned_this_toss = true

	if not is_instance_valid(player):
		return

	var spore := _MushroomSpore.new()
	spore.source = self
	spore.damage = attack_damage

	var facing : float = -1.0 if sprite.flip_h else 1.0
	spore.global_position = global_position + Vector2(facing * 10.0, -30.0)

	var target := player.global_position
	var diff := target - spore.global_position
	spore.vel = Vector2(diff.x * 1.2, minf(diff.y * 0.8, -80.0))

	get_parent().add_child(spore)


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
	if state in [State.DEAD, State.ATTACK, State.SPORE, State.HURT]:
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
	elif state == State.SPORE:
		if sprite.frame == 7:
			_spawn_spore()


func _on_animation_finished():
	match sprite.animation:
		"Attack", "Attack2":
			hitbox_shape.disabled = true
			attack_hit_bodies.clear()
			resume_after_action()
		"ThrowProjectile":
			_spore_spawned_this_toss = false
			resume_after_action()
		"Hit":
			resume_after_action()


# ═══════════════════════════════════════════
#  SPORE PROJECTILE — lingering poison cloud
# ═══════════════════════════════════════════

class _MushroomSpore extends Area2D:
	const SPORE_GRAVITY := 300.0
	const CLOUD_LIFETIME := 3.0
	const CLOUD_TICK_INTERVAL := 0.5
	const CLOUD_RADIUS := 20.0

	var vel := Vector2.ZERO
	var damage := 1
	var source: Node2D
	var has_landed := false
	var cloud_timer := 0.0
	var tick_timer := 0.0
	var spore_sprite: AnimatedSprite2D
	var floor_ray: RayCast2D
	var cloud_shape: CollisionShape2D

	func _ready():
		collision_layer = 0
		collision_mask = 2
		monitoring = true

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 4.0
		col.shape = circle
		add_child(col)

		floor_ray = RayCast2D.new()
		floor_ray.target_position = Vector2(0, 6)
		floor_ray.collision_mask = 3
		floor_ray.enabled = true
		add_child(floor_ray)

		var sheet : Texture2D = load("res://Assets/sprites/Mobs/Monsters_Creatures_Fantasy/Monster_Creatures_Fantasy(Version 1.3)/Mushroom/Projectile_sprite.png")
		var frames := SpriteFrames.new()

		frames.add_animation("fly")
		frames.set_animation_speed("fly", 8.0)
		frames.set_animation_loop("fly", true)
		for i in range(4):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 50.0, 0, 50, 50)
			frames.add_frame("fly", tex)

		frames.add_animation("cloud")
		frames.set_animation_speed("cloud", 6.0)
		frames.set_animation_loop("cloud", true)
		for i in range(4, 8):
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(float(i) * 50.0, 0, 50, 50)
			frames.add_frame("cloud", tex)

		spore_sprite = AnimatedSprite2D.new()
		spore_sprite.sprite_frames = frames
		spore_sprite.play("fly")
		add_child(spore_sprite)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float):
		if has_landed:
			cloud_timer -= delta
			tick_timer -= delta

			if tick_timer <= 0.0:
				tick_timer = CLOUD_TICK_INTERVAL
				for body in get_overlapping_bodies():
					if body.is_in_group("Player") and body.has_method("take_damage"):
						body.take_damage(damage, global_position, source)

			if cloud_timer <= 1.0:
				spore_sprite.modulate.a = cloud_timer

			if cloud_timer <= 0.0:
				queue_free()
			return

		vel.y += SPORE_GRAVITY * delta
		position += vel * delta

		if floor_ray.is_colliding() and vel.y > 0.0:
			_become_cloud()

	func _on_body_entered(body: Node2D):
		if body.is_in_group("Player") and body.has_method("take_damage"):
			body.take_damage(damage, global_position, source)
			if not has_landed:
				_become_cloud()

	func _become_cloud():
		has_landed = true
		vel = Vector2.ZERO
		cloud_timer = CLOUD_LIFETIME
		tick_timer = CLOUD_TICK_INTERVAL

		if floor_ray.is_colliding():
			position.y = floor_ray.get_collision_point().y - 4.0

		(get_child(0) as CollisionShape2D).shape.radius = CLOUD_RADIUS

		spore_sprite.play("cloud")
		spore_sprite.scale = Vector2(2.0, 2.0)


# ═══════════════════════════════════════════
#  DAMAGE & DEATH
# ═══════════════════════════════════════════

func _on_hurt():
	state = State.HURT
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	_spore_spawned_this_toss = false
	apply_knockback()
	play_anim("Hit")


func _on_die():
	state = State.DEAD
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	velocity = Vector2.ZERO
	die_with_fadeout()
