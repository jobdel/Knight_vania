extends EnemyBase

# --------------------
# State Machine
# --------------------
enum State { HOVER, SWOOP, RETURN, HURT, DEAD }
var state : State = State.HOVER

# --------------------
# Stats
# --------------------
const HOVER_BOB_SPEED := 2.0
const HOVER_BOB_AMP := 6.0
const SWOOP_SPEED := 110.0
const RETURN_SPEED := 50.0
const SWOOP_RANGE := 60.0
const PATROL_SPEED := 20.0
const PATROL_DISTANCE := 50.0

# Hover
var spawn_pos := Vector2.ZERO
var bob_time := 0.0
var patrol_dir := 1

# Swoop
var swoop_target := Vector2.ZERO
var swoop_cooldown := 0.0
const SWOOP_COOLDOWN := 2.0

# --------------------
# Nodes
# --------------------
var contact_area: Area2D
var contact_shape: CollisionShape2D

const IDLE_SHEET := "res://Assets/sprites/craft pix/Enemies/Alien4_Idle.png"
const JUMP_SHEET := "res://Assets/sprites/craft pix/Enemies/Alien4_Jump.png"
const RUN_SHEET := "res://Assets/sprites/craft pix/Enemies/Alien_Run.png"


func _ready():
	max_health = 1
	knockback_force = Vector2(60, -80)
	aggro_memory = 0.0
	contact_damage = 1

	init_enemy()

	spawn_pos = global_position
	sprite.scale = Vector2(0.5, 0.5)

	_setup_sprite_frames()
	_setup_contact_area()
	setup_aggro_area(80.0)
	setup_health_bar(Vector2(20, 2), Vector2(-10, -20))
	play_anim("idle")


func _setup_sprite_frames():
	var frames := SpriteFrames.new()

	add_sheet_anim(frames, "idle", IDLE_SHEET, 4, 46, 47, 8.0, true)
	add_sheet_anim(frames, "swoop", JUMP_SHEET, 5, 46, 42, 10.0, false)
	add_sheet_anim(frames, "fly", RUN_SHEET, 5, 46, 27, 10.0, true)

	if frames.has_animation("default"):
		frames.remove_animation("default")

	sprite.sprite_frames = frames


func _setup_contact_area():
	contact_area = Area2D.new()
	contact_area.collision_layer = 0
	contact_area.collision_mask = 2
	contact_area.monitoring = true

	contact_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	contact_shape.shape = shape

	contact_area.add_child(contact_shape)
	add_child(contact_area)


# --------------------
# Detection overrides
# --------------------
func _on_player_lost():
	player = null


func _is_dead() -> bool:
	return state == State.DEAD


# --------------------
# Physics
# --------------------
func _physics_process(delta: float):
	if state == State.DEAD:
		return

	if swoop_cooldown > 0.0:
		swoop_cooldown -= delta

	update_enemy_commons(delta)

	match state:
		State.HOVER:
			_state_hover(delta)
		State.SWOOP:
			_state_swoop(delta)
		State.RETURN:
			_state_return(delta)
		State.HURT:
			_state_hurt(delta)

	global_position += velocity * delta
	_check_contact()


# --------------------
# Hover
# --------------------
func _state_hover(delta: float):
	bob_time += delta

	var offset_x : float = global_position.x - spawn_pos.x
	if offset_x >= PATROL_DISTANCE:
		patrol_dir = -1
	elif offset_x <= -PATROL_DISTANCE:
		patrol_dir = 1

	velocity.x = float(patrol_dir) * PATROL_SPEED
	velocity.y = sin(bob_time * HOVER_BOB_SPEED) * HOVER_BOB_AMP * 4.0
	sprite.flip_h = patrol_dir < 0

	if is_instance_valid(player) and swoop_cooldown <= 0.0:
		var dist : float = global_position.distance_to(player.global_position)
		if dist <= SWOOP_RANGE:
			_start_swoop()

	play_anim("idle")


# --------------------
# Swoop
# --------------------
func _start_swoop():
	state = State.SWOOP
	swoop_target = player.global_position + Vector2(0, -5)
	play_anim("swoop")

	var dir : float = signf(swoop_target.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	sprite.flip_h = dir < 0.0


func _state_swoop(delta: float):
	var dir_vec := (swoop_target - global_position).normalized()
	velocity = dir_vec * SWOOP_SPEED

	if global_position.distance_to(swoop_target) < 8.0:
		state = State.RETURN
		swoop_cooldown = SWOOP_COOLDOWN
		play_anim("fly")


# --------------------
# Return
# --------------------
func _state_return(delta: float):
	var dir_vec := (spawn_pos - global_position).normalized()
	velocity = dir_vec * RETURN_SPEED

	if global_position.distance_to(spawn_pos) < 4.0:
		global_position = spawn_pos
		velocity = Vector2.ZERO
		state = State.HOVER
		bob_time = 0.0


# --------------------
# Hurt
# --------------------
func _state_hurt(delta: float):
	velocity = velocity.move_toward(Vector2.ZERO, 100.0 * delta)
	if velocity.length() < 10.0:
		state = State.RETURN
		play_anim("fly")


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

	play_anim("swoop")
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", global_position.y + 60.0, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
