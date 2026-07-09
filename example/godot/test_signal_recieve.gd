extends Node2D


func _ready():
	var player = get_parent().get_node("Player")
	player.hit.connect(_on_hit)

func _on_hit(amount: int):
	print("hit read from gdscript ", amount)
