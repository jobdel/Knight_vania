extends Node2D

## Blast explosion — damages enemies in radius, plays sunburn spritesheet animation.

const SHEET_PATH := "res://Assets/sprites/Free Pixel Effects Pack/1_magicspell_spritesheet.png"
const FRAME_SIZE := 100
const COLS := 9
const TOTAL_FRAMES := 20
const BLAST_DURATION := 0.2
const FPS := float(TOTAL_FRAMES) / BLAST_DURATION

var damage := 1
var radius := 60.0
var source_body: CharacterBody2D  # Player who spawned this

var anim_sprite: AnimatedSprite2D
var hit_area: Area2D
var has_dealt_damage := false


func _ready():
	# --- Build AnimatedSprite2D from spritesheet ---
	var sheet : Texture2D = load(SHEET_PATH)
	var frames := SpriteFrames.new()
	frames.add_animation("explode")
	frames.set_animation_speed("explode", FPS)
	frames.set_animation_loop("explode", false)

	for i in TOTAL_FRAMES:
		var col := i % COLS
		var row := i / COLS
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame("explode", atlas)

	# Remove default animation if it exists
	if frames.has_animation("default"):
		frames.remove_animation("default")

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = frames
	anim_sprite.scale = Vector2(0.5, 0.5)
	anim_sprite.z_index = 10
	add_child(anim_sprite)

	# --- Damage area (circle) ---
	hit_area = Area2D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = 8  # Enemy bodies
	hit_area.monitoring = true

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	col_shape.shape = circle
	hit_area.add_child(col_shape)
	add_child(hit_area)

	# Play
	anim_sprite.play("explode")
	anim_sprite.animation_finished.connect(_on_finished)


func _physics_process(_delta: float):
	if has_dealt_damage:
		return
	for body in hit_area.get_overlapping_bodies():
		if body == source_body:
			continue
		if body.is_in_group("Enemy") and body.has_method("take_damage"):
			body.take_damage(damage)
	has_dealt_damage = true


func _on_finished():
	queue_free()
