extends Area2D

@onready var timer = $Timer


func _ready():
	monitoring = true


func _on_body_entered(body: Node):
	if not body.is_in_group("Player"):
		return

	print("You dead boi")
	timer.start()


func _on_timer_timeout():
	get_tree().reload_current_scene()
