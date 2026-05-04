extends Area2D

const GRENADE_GRAVITY := 500.0
const FUSE_TIME := 2.0
const EXPLOSION_RADIUS := 50.0
const EXPLOSION_DAMAGE := 2
const BOUNCE_DAMPEN := 0.5

var vel := Vector2.ZERO
var fuse_timer := FUSE_TIME
var exploded := false

# Visuals
var grenade_sprite: Polygon2D
var flash_timer := 0.0


func _ready():
	collision_layer = 0
	collision_mask = 2 | 8   # Terrain + enemies
	monitoring = true

	# Grenade body shape (small circle for collision)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	add_child(col)

	# Draw a small grenade (dark green circle with a lighter top)
	grenade_sprite = Polygon2D.new()
	var points : PackedVector2Array = PackedVector2Array()
	for i in 12:
		var angle := float(i) / 12.0 * TAU
		points.append(Vector2(cos(angle) * 5.0, sin(angle) * 5.0))
	grenade_sprite.polygon = points
	grenade_sprite.color = Color(0.25, 0.35, 0.2)
	add_child(grenade_sprite)


func _physics_process(delta: float):
	if exploded:
		return

	# Gravity
	vel.y += GRENADE_GRAVITY * delta
	var motion := vel * delta

	# Simple terrain check via raycast
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + motion, 2)
	var result := space.intersect_ray(query)

	if result:
		global_position = result.position
		# Bounce off terrain
		var normal : Vector2 = result.normal
		vel = vel.bounce(normal) * BOUNCE_DAMPEN
		# Kill horizontal slide when slow enough
		if absf(vel.y) < 20.0 and absf(vel.x) < 20.0:
			vel = Vector2.ZERO
	else:
		global_position += motion

	# Fuse countdown
	fuse_timer -= delta

	# Flash faster as fuse runs out
	flash_timer += delta
	var flash_rate := lerpf(0.4, 0.08, 1.0 - fuse_timer / FUSE_TIME)
	if fmod(flash_timer, flash_rate * 2.0) < flash_rate:
		grenade_sprite.color = Color(0.9, 0.2, 0.1)
	else:
		grenade_sprite.color = Color(0.25, 0.35, 0.2)

	if fuse_timer <= 0.0:
		_explode()


func _explode():
	exploded = true
	grenade_sprite.visible = false

	# Find all enemies in explosion radius
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = EXPLOSION_RADIUS
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 8   # Layer 4 — enemies
	query.collide_with_bodies = true

	var results := space.intersect_shape(query, 16)
	for hit in results:
		var body : Node2D = hit.collider as Node2D
		if body != null and body.is_in_group("Enemy") and body.has_method("take_damage"):
			body.take_damage(EXPLOSION_DAMAGE)

	# Draw explosion flash then remove
	_draw_explosion()
	await get_tree().create_timer(0.15).timeout
	queue_free()


func _draw_explosion():
	var flash := Polygon2D.new()
	var points : PackedVector2Array = PackedVector2Array()
	for i in 16:
		var angle := float(i) / 16.0 * TAU
		points.append(Vector2(cos(angle) * EXPLOSION_RADIUS, sin(angle) * EXPLOSION_RADIUS))
	flash.polygon = points
	flash.color = Color(1.0, 0.6, 0.1, 0.7)
	add_child(flash)

	# Fade out
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.15)
