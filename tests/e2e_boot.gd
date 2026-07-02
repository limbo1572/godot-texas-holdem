extends Node
## Bootstrap for E2E scenes: spawns the driver under /root so it survives
## the lobby -> table scene change, then this scene node becomes irrelevant.

@export var role: String = "host"


func _ready() -> void:
	var driver := Node.new()
	driver.name = "E2EDriver"
	driver.set_script(load("res://tests/e2e_driver.gd"))
	driver.set("role", role)
	get_tree().root.add_child.call_deferred(driver)
