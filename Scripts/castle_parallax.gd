extends ParallaxBackground

## Castle parallax — moonlit night sky, distant castle silhouettes, ground fog.

@export var bg_layer_1: Texture2D  # Moon/sky
@export var bg_layer_2: Texture2D  # Castle silhouettes
@export var bg_layer_3: Texture2D  # Ground mist

const SKY_COLOR := Color(0.08, 0.09, 0.18)
const IMG_W := 320.0


func _ready():
	for child in get_children():
		child.queue_free()

	_add_sky_layer()
	_add_parallax_layer(bg_layer_1, Vector2(0.03, 0.01), Vector2(0, -230), Color.WHITE, "MoonSky")
	_add_parallax_layer(bg_layer_2, Vector2(0.12, 0.04), Vector2(0, -90), Color(0.8, 0.8, 0.9), "CastleFar")
	_add_parallax_layer(bg_layer_2, Vector2(0.25, 0.06), Vector2(160, -80), Color(0.6, 0.6, 0.7), "CastleMid")
	_add_parallax_layer(bg_layer_3, Vector2(0.5, 0.08), Vector2(0, -20), Color(0.9, 0.85, 0.8), "GroundMist")


func _add_sky_layer():
	var layer := ParallaxLayer.new()
	layer.name = "SkyFill"
	layer.motion_scale = Vector2(0.0, 0.0)

	var rect := ColorRect.new()
	rect.color = SKY_COLOR
	rect.position = Vector2(-2000, -500)
	rect.size = Vector2(6000, 1500)

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
