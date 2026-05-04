extends ParallaxBackground

## Production parallax with 5 visual layers:
## 0. Solid sky color fill (never gaps)
## 1. Far sky/mist (background_layer_1) — barely moves
## 2. Far trees (background_layer_2) — slow scroll, tinted darker
## 3. Mid trees (background_layer_2) — offset copy for depth
## 4. Near trees (background_layer_3) — closest, fastest scroll

@export var bg_layer_1: Texture2D
@export var bg_layer_2: Texture2D
@export var bg_layer_3: Texture2D

const SKY_COLOR := Color(0.42, 0.45, 0.65)  # Muted blue-purple to match Oak Woods palette
const IMG_W := 320.0
const IMG_H := 180.0


func _ready():
	# Remove any editor-placed children (we build everything in code)
	for child in get_children():
		child.queue_free()

	_add_sky_layer()
	_add_parallax_layer(bg_layer_1, Vector2(0.05, 0.02), Vector2(0, -120), Color(0.85, 0.85, 0.95), "SkyMist")
	_add_parallax_layer(bg_layer_2, Vector2(0.15, 0.05), Vector2(0, -110), Color(0.7, 0.65, 0.75), "FarTrees")
	_add_parallax_layer(bg_layer_2, Vector2(0.3, 0.08), Vector2(160, -100), Color(0.85, 0.8, 0.85), "MidTrees")
	_add_parallax_layer(bg_layer_3, Vector2(0.55, 0.1), Vector2(0, -95), Color.WHITE, "NearTrees")


func _add_sky_layer():
	var layer := ParallaxLayer.new()
	layer.name = "SkyFill"
	layer.motion_scale = Vector2(0.0, 0.0)

	var rect := ColorRect.new()
	rect.color = SKY_COLOR
	# Large enough to always cover the viewport regardless of camera position
	rect.position = Vector2(-2000, -500)
	rect.size = Vector2(4000, 1000)

	layer.add_child(rect)
	add_child(layer)


func _add_parallax_layer(tex: Texture2D, motion: Vector2, offset: Vector2, tint: Color, layer_name: String):
	if tex == null:
		return

	var layer := ParallaxLayer.new()
	layer.name = layer_name
	layer.motion_scale = motion
	layer.motion_mirroring = Vector2(IMG_W, 0)

	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.position = offset
	spr.modulate = tint

	layer.add_child(spr)
	add_child(layer)
