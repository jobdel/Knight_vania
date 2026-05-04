extends EnemyBase

# ═══════════════════════════════════════════
#  STATE MACHINE
# ═══════════════════════════════════════════

enum State { PATROL, CHASE, ATTACK, HURT, DEAD }
var state : State = State.PATROL

# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

const SPEED := 60.0
const GRAVITY := 900.0
const ATTACK_RANGE := 35.0
const ATTACK_COOLDOWN := 1.0
const PATROL_DISTANCE := 80.0

# ═══════════════════════════════════════════
#  STATE VARIABLES
# ═══════════════════════════════════════════

var spawn_x := 0.0
var patrol_dir := 1
var patrol_wait := 0.0
var attack_cooldown_timer := 0.0
var current_attack := 0
var attack_hit_bodies : Array = []

# ═══════════════════════════════════════════
#  NODES (scene-based)
# ═══════════════════════════════════════════

@onready var detect_cone: Area2D = $DetectCone
@onready var body_hitbox: CollisionShape2D = $HitBox

var attack_hitbox: Area2D
var hitbox_shape: CollisionShape2D


# ═══════════════════════════════════════════
#  READY & SETUP
# ═══════════════════════════════════════════

func _ready():
	max_health = 3
	knockback_force = Vector2(80, -60)
	aggro_memory = 2.5
	contact_damage = 1
	attack_damage = 1

	init_enemy()

	spawn_x = global_position.x
	body_hitbox.disabled = true

	setup_anim_config(["Attack1", "Attack2", "Hurt", "Die"])

	sprite.animation_finished.connect(_on_animation_finished)
	detect_cone.body_entered.connect(_on_detect_entered)
	detect_cone.body_exited.connect(_on_detect_exited)

	_setup_attack_hitbox()
	setup_edge_detector(15.0, 30.0)
	setup_health_bar(Vector2(28, 3), Vector2(-14, -40))
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
	hitbox_shape.position = Vector2(25, -25)
	hitbox_shape.rotation = PI / 2.0
	hitbox_shape.disabled = true

	attack_hitbox.add_child(hitbox_shape)
	add_child(attack_hitbox)


# ═══════════════════════════════════════════
#  DETECTION (scene-based DetectCone)
# ═══════════════════════════════════════════

func _on_detect_entered(body: Node):
	if body.is_in_group("Player"):
		player = body
		aggro_timer = 0.0
		if state == State.PATROL:
			state = State.CHASE


func _on_detect_exited(body: Node):
	if body == player:
		aggro_timer = aggro_memory


func _is_dead() -> bool:
	return state == State.DEAD


func _enter_combat_state():
	state = State.CHASE


func _enter_idle_state():
	state = State.PATROL
	player = null
	aggro_timer = 0.0


# ═══════════════════════════════════════════
#  PHYSICS MAIN
# ═══════════════════════════════════════════

func _physics_process(delta: float):
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta

	update_enemy_commons(delta)

	match state:
		State.HURT:
			move_and_check_player()
			return
		State.ATTACK:
			_process_attack_hits()
			move_and_check_player()
			return
		State.CHASE:
			_state_chase()
		State.PATROL:
			_state_patrol(delta)

	move_and_check_player()
	_update_animation()


# ═══════════════════════════════════════════
#  STATE: PATROL
# ═══════════════════════════════════════════

func _state_patrol(delta: float):
	update_edge_ray_facing()

	if has_target():
		state = State.CHASE
		return

	if patrol_wait > 0.0:
		patrol_wait -= delta
		velocity.x = 0
		return

	var offset : float = global_position.x - spawn_x
	if offset >= PATROL_DISTANCE:
		patrol_dir = -1
		patrol_wait = 1.5
		velocity.x = 0
		return
	elif offset <= -PATROL_DISTANCE:
		patrol_dir = 1
		patrol_wait = 1.5
		velocity.x = 0
		return

	if is_on_floor() and not edge_ray.is_colliding():
		patrol_dir = -patrol_dir
		patrol_wait = 1.0
		velocity.x = 0
		return

	velocity.x = float(patrol_dir) * SPEED * 0.5
	_face_with_cone(patrol_dir)


# ═══════════════════════════════════════════
#  STATE: CHASE
# ═══════════════════════════════════════════

func _state_chase():
	update_edge_ray_facing()

	if not has_target():
		state = State.PATROL
		return

	if not is_instance_valid(player):
		state = State.PATROL
		return

	var diff : float = player.global_position.x - global_position.x
	var dist : float = absf(diff)
	var dir : int = safe_dir(diff)

	if dist <= ATTACK_RANGE:
		velocity.x = 0
		_face_with_cone(dir)
		_try_attack()
	else:
		if is_on_floor() and not edge_ray.is_colliding():
			velocity.x = 0
			return
		velocity.x = float(dir) * SPEED
		_face_with_cone(dir)


# ═══════════════════════════════════════════
#  STATE: ATTACK
# ═══════════════════════════════════════════

func _try_attack():
	if attack_cooldown_timer > 0.0:
		return

	state = State.ATTACK
	velocity.x = 0
	attack_cooldown_timer = ATTACK_COOLDOWN
	attack_hit_bodies.clear()
	hitbox_shape.disabled = false

	if current_attack == 0:
		play_anim("Attack1")
	else:
		play_anim("Attack2")
	current_attack = (current_attack + 1) % 2


func _process_attack_hits():
	for body in attack_hitbox.get_overlapping_bodies():
		if body in attack_hit_bodies:
			continue
		if body.is_in_group("Player") and body.has_method("take_damage"):
			attack_hit_bodies.append(body)
			body.take_damage(attack_damage, global_position)


# ═══════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════

func _face_with_cone(dir: int):
	face_dir(dir)
	detect_cone.rotation = 0.0 if dir > 0 else PI
	hitbox_shape.position.x = -25.0 if dir < 0 else 25.0


func _update_animation():
	if state in [State.DEAD, State.ATTACK, State.HURT]:
		return
	if not is_on_floor():
		play_anim("Jump")
	elif velocity.x != 0:
		play_anim("Walk")
	else:
		play_anim("Idle")


func _on_animation_finished():
	match sprite.animation:
		"Attack1", "Attack2":
			hitbox_shape.disabled = true
			attack_hit_bodies.clear()
			resume_after_action()
		"Hurt":
			resume_after_action()


# ═══════════════════════════════════════════
#  DAMAGE & DEATH
# ═══════════════════════════════════════════

func _on_hurt():
	state = State.HURT
	hitbox_shape.disabled = true
	attack_hit_bodies.clear()
	apply_knockback()
	play_anim("Hurt")


func _on_die():
	state = State.DEAD
	hitbox_shape.disabled = true
	velocity = Vector2.ZERO
	die_with_fadeout("Die")
