extends Area2D

## Animated spike/flame column trap. Deals damage on contact.
## Uses Trap4.png — 8 frames of 48x48 flame pillars.

const TRAP_SHEET := "res://Assets/sprites/craft pix/Traps/Trap4.png"
const DAMAGE := 1
const DAMAGE_INTERVAL := 0.8

var damage_cooldowns : Dictionary = {}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready():
	collision_layer = 0
	collision_mask = 2
	monitoring = true

	sprite.scale = Vector2(0.5, 0.5)
	_setup_sprite_frames()
	_setup_hitbox()

	play_anim("burn")


func _setup_sprite_frames():
	var frames := SpriteFrames.new()
	var tex := load(TRAP_SHEET) as Texture2D

	frames.add_animation("burn")
	frames.set_animation_speed("burn", 10.0)
	frames.set_animation_loop("burn", true)
	for i in 8:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(i * 48), 0.0, 48.0, 48.0)
		frames.add_frame("burn", atlas)

	if frames.has_animation("default"):
		frames.remove_animation("default")

	sprite.sprite_frames = frames


func _setup_hitbox():
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 20)
	col.shape = shape
	col.position = Vector2(0, -10)
	add_child(col)


func _physics_process(delta: float):
	# Tick damage cooldowns
	for key in damage_cooldowns.keys():
		damage_cooldowns[key] -= delta
		if damage_cooldowns[key] <= 0.0:
			damage_cooldowns.erase(key)

	# Re-check overlapping bodies for repeat damage
	for body in get_overlapping_bodies():
		if body.is_in_group("Player") and body.has_method("take_damage"):
			var id : int = body.get_instance_id()
			if not damage_cooldowns.has(id):
				body.take_damage(DAMAGE, global_position)
				damage_cooldowns[id] = DAMAGE_INTERVAL


func play_anim(anim_name: String):
	if sprite.animation != anim_name:
		sprite.play(anim_name)
