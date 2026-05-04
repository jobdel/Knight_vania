extends Area2D

## Spinning saw blade trap. Moves between two points and damages on contact.
## Uses Trap5.png — 4 frames of 48x64 spinning shuriken.

const TRAP_SHEET := "res://Assets/sprites/craft pix/Traps/Trap5.png"
const DAMAGE := 1
const DAMAGE_INTERVAL := 0.6

## Movement: the saw patrols between spawn and spawn + travel_offset
@export var travel_offset := Vector2(60, 0)
@export var travel_speed := 40.0

var spawn_pos := Vector2.ZERO
var moving_to_end := true
var damage_cooldowns : Dictionary = {}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready():
	collision_layer = 0
	collision_mask = 2
	monitoring = true

	spawn_pos = global_position
	sprite.scale = Vector2(0.4, 0.4)

	_setup_sprite_frames()
	_setup_hitbox()

	play_anim("spin")


func _setup_sprite_frames():
	var frames := SpriteFrames.new()
	var tex := load(TRAP_SHEET) as Texture2D

	frames.add_animation("spin")
	frames.set_animation_speed("spin", 12.0)
	frames.set_animation_loop("spin", true)
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(i * 48), 0.0, 48.0, 64.0)
		frames.add_frame("spin", atlas)

	if frames.has_animation("default"):
		frames.remove_animation("default")

	sprite.sprite_frames = frames


func _setup_hitbox():
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	col.shape = shape
	add_child(col)


func _physics_process(delta: float):
	# Move between endpoints
	var target := spawn_pos + travel_offset if moving_to_end else spawn_pos
	var dir := (target - global_position).normalized()
	var dist := global_position.distance_to(target)

	if dist < 2.0:
		moving_to_end = not moving_to_end
	else:
		global_position += dir * minf(travel_speed * delta, dist)

	# Tick damage cooldowns
	for key in damage_cooldowns.keys():
		damage_cooldowns[key] -= delta
		if damage_cooldowns[key] <= 0.0:
			damage_cooldowns.erase(key)

	# Re-check for repeat damage
	for body in get_overlapping_bodies():
		if body.is_in_group("Player") and body.has_method("take_damage"):
			var id : int = body.get_instance_id()
			if not damage_cooldowns.has(id):
				body.take_damage(DAMAGE, global_position)
				damage_cooldowns[id] = DAMAGE_INTERVAL


func play_anim(anim_name: String):
	if sprite.animation != anim_name:
		sprite.play(anim_name)
