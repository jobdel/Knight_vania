class_name EnemyBase
extends CharacterBody2D

# ═══════════════════════════════════════════
#  SHARED STATE
# ═══════════════════════════════════════════

var max_health := 2
var health := 2
var attack_damage := 1

var player: Node2D = null
var aggro_timer := 0.0
var aggro_memory := 2.5
var last_known_player_pos := Vector2.ZERO

var flash_timer := 0.0
var health_bar_visible_timer := 0.0
var ever_hit := false

var knockback_force := Vector2(60, -100)
var contact_damage := 1

const FLASH_DURATION := 0.12
const HEALTH_BAR_SHOW_TIME := 4.0

# ═══════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var aggro_area: Area2D
var edge_ray: RayCast2D
var health_bar: ProgressBar


# ═══════════════════════════════════════════
#  SETUP — call from subclass _ready()
# ═══════════════════════════════════════════

## Call first in subclass _ready() after setting max_health, knockback_force, etc.
func init_enemy():
	add_to_group("Enemy")
	collision_layer = 8
	collision_mask = 3
	health = max_health


func setup_aggro_area(radius: float, offset := Vector2.ZERO):
	aggro_area = Area2D.new()
	aggro_area.collision_layer = 0
	aggro_area.collision_mask = 2
	aggro_area.monitoring = true

	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	col.shape = circle
	col.position = offset

	aggro_area.add_child(col)
	add_child(aggro_area)

	aggro_area.body_entered.connect(_on_aggro_entered)
	aggro_area.body_exited.connect(_on_aggro_exited)


func setup_edge_detector(offset_x: float, depth: float):
	edge_ray = RayCast2D.new()
	edge_ray.position = Vector2(offset_x, 0.0)
	edge_ray.target_position = Vector2(0.0, depth)
	edge_ray.collision_mask = 3
	edge_ray.enabled = true
	add_child(edge_ray)


func setup_health_bar(bar_size: Vector2, bar_pos: Vector2):
	health_bar = ProgressBar.new()
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = bar_size
	health_bar.size = bar_size
	health_bar.position = bar_pos
	health_bar.modulate.a = 0.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	health_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.1, 0.1)
	health_bar.add_theme_stylebox_override("fill", fill)

	add_child(health_bar)


# ═══════════════════════════════════════════
#  PER-FRAME — call from subclass _physics_process()
# ═══════════════════════════════════════════

## Updates hit flash, health bar fade, and aggro timer
func update_enemy_commons(delta: float):
	if aggro_timer > 0.0:
		aggro_timer -= delta

	if flash_timer > 0.0:
		flash_timer -= delta
		sprite.modulate = Color(3.0, 3.0, 3.0)
		if flash_timer <= 0.0:
			sprite.modulate = Color.WHITE

	if health_bar != null:
		if not ever_hit:
			health_bar.visible = false
		elif health_bar_visible_timer > 0.0:
			health_bar.visible = true
			health_bar_visible_timer -= delta
			if health_bar_visible_timer <= 0.5:
				health_bar.modulate.a = health_bar_visible_timer / 0.5
		else:
			health_bar.visible = false


## Flips edge ray to match sprite facing direction
func update_edge_ray_facing():
	if edge_ray == null:
		return
	var facing : float = -1.0 if sprite.flip_h else 1.0
	edge_ray.position.x = facing * absf(edge_ray.position.x)


# ═══════════════════════════════════════════
#  DETECTION
# ═══════════════════════════════════════════

func _on_aggro_entered(body: Node2D):
	if body.is_in_group("Player"):
		player = body
		aggro_timer = 0.0
		_on_player_spotted()


func _on_aggro_exited(body: Node2D):
	if body == player:
		_on_player_lost()
		aggro_timer = aggro_memory


## Override to react when player enters aggro (e.g. enter chase/alert state)
func _on_player_spotted():
	pass


## Override to store last_known_player_pos or clear player reference
func _on_player_lost():
	pass


func has_target() -> bool:
	if is_instance_valid(player):
		return true
	return aggro_timer > 0.0


# ═══════════════════════════════════════════
#  DAMAGE
# ═══════════════════════════════════════════

func take_damage(amount := 1):
	if _is_dead():
		return
	if _on_damage_blocked(amount):
		return

	health -= amount
	_show_health_bar()
	flash_timer = FLASH_DURATION
	_re_aggro_on_hit()

	if health <= 0:
		_on_die()
	else:
		_on_hurt()


func _show_health_bar():
	if health_bar == null:
		return
	ever_hit = true
	health_bar.value = health
	health_bar.modulate.a = 1.0
	health_bar_visible_timer = HEALTH_BAR_SHOW_TIME


func _re_aggro_on_hit():
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			player = players[0]
			aggro_timer = aggro_memory


## Override: return true to block damage (e.g. shield)
func _on_damage_blocked(_amount: int) -> bool:
	return false


## Override: enter hurt state, apply knockback
func _on_hurt():
	pass


## Override: enter dead state, play death anim
func _on_die():
	pass


## Override: return true when in dead state
func _is_dead() -> bool:
	return false


# ═══════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════

func play_anim(anim_name: String):
	if sprite.animation != anim_name:
		sprite.play(anim_name)


func face_dir(dir: int):
	sprite.flip_h = dir < 0


## signf() that returns 1 instead of 0 when positions are equal
func safe_dir(value: float) -> int:
	var d := int(signf(value))
	if d == 0:
		d = 1
	return d


## Apply knockback away from player using knockback_force
func apply_knockback():
	var kb_dir := 1.0
	if is_instance_valid(player):
		kb_dir = signf(global_position.x - player.global_position.x)
		if kb_dir == 0.0:
			kb_dir = 1.0
	velocity = Vector2(kb_dir * knockback_force.x, knockback_force.y)


## move_and_slide + deal contact damage on body collisions with player
func move_and_check_player():
	move_and_slide()
	if _is_dead():
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node and collider.is_in_group("Player"):
			var bounce_dir := signf(global_position.x - collider.global_position.x)
			if bounce_dir == 0.0:
				bounce_dir = 1.0
			velocity.x = bounce_dir * 100.0
			velocity.y = -200.0
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage, global_position, self)


## Standard death: disable collision, play anim, fade out, queue_free
func die_with_fadeout(death_anim := "Death"):
	collision_layer = 0
	collision_mask = 0
	play_anim(death_anim)
	await sprite.animation_finished
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


## Configure animation playback: set listed names to non-looping, multiply all speeds.
func setup_anim_config(non_looping: Array, speed_mult := 1.0):
	for anim_name in non_looping:
		if sprite.sprite_frames.has_animation(anim_name):
			sprite.sprite_frames.set_animation_loop(anim_name, false)
	if speed_mult != 1.0:
		for anim_name in sprite.sprite_frames.get_animation_names():
			var spd : float = sprite.sprite_frames.get_animation_speed(anim_name)
			sprite.sprite_frames.set_animation_speed(anim_name, spd * speed_mult)


## Resume to chase or patrol after an interruptible action.
## Subclasses must override _enter_combat_state() and _enter_idle_state().
func resume_after_action():
	if has_target():
		_enter_combat_state()
	else:
		_enter_idle_state()


## Override: re-enter combat (e.g. chase) after hurt/attack finishes
func _enter_combat_state():
	pass


## Override: return to idle (e.g. patrol) after hurt/attack finishes
func _enter_idle_state():
	pass


## Build animation from a horizontal sprite sheet strip
func add_sheet_anim(frames: SpriteFrames, anim_name: String, path: String,
		frame_count: int, fw: int, fh: int, speed: float, looping: bool):
	var tex := load(path) as Texture2D
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, speed)
	frames.set_animation_loop(anim_name, looping)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
		frames.add_frame(anim_name, atlas)
