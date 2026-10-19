extends Node3D
## Circular landing zone on the ground. Only the horizontal distance is checked;
## the mission separately requires the drone to be resting on the ground.

@export var radius := 4.0 ## m


func contains(world_position: Vector3) -> bool:
	var offset := world_position - global_position
	return Vector2(offset.x, offset.z).length() <= radius
