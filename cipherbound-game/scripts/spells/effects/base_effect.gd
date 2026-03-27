extends Node3D
class_name BaseSpellEffect
## Base class for all spell visual effects.
## Handles particles, lifetime, and damage to enemies via Area3D.

signal effect_finished

## How long before auto-cleanup
@export var lifetime := 2.0
## Damage dealt to enemies in range
@export var damage := 0.0
## Radius for damage area (0 = no damage area)
@export var damage_radius := 0.0
## Whether damage is applied once or continuously
@export var damage_once := true

var _elapsed := 0.0
var _particles: Array[GPUParticles3D] = []
var _damaged_enemies: Array[Node] = []
var _damage_area: Area3D = null

func _ready() -> void:
	_collect_particles()
	
	# Create damage area if configured
	if damage > 0 and damage_radius > 0:
		_create_damage_area()
	
	play()

func _collect_particles() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			_particles.append(child)

func _process(delta: float) -> void:
	_elapsed += delta
	_on_update(delta)
	
	# Apply damage
	if _damage_area and damage > 0:
		_apply_damage()
	
	if _elapsed >= lifetime:
		_cleanup()

func play() -> void:
	"""Start all particle emitters."""
	for p in _particles:
		p.emitting = true

func stop() -> void:
	"""Stop all particle emitters."""
	for p in _particles:
		p.emitting = false

func _cleanup() -> void:
	effect_finished.emit()
	queue_free()

func _on_update(_delta: float) -> void:
	"""Override in subclass for per-frame updates."""
	pass

## Utility: Instantiate a particle scene and add as child
func add_particle_scene(scene: PackedScene) -> GPUParticles3D:
	var instance := scene.instantiate()
	if instance is GPUParticles3D:
		add_child(instance)
		_particles.append(instance)
		return instance
	else:
		instance.queue_free()
		push_warning("BaseSpellEffect: Scene is not GPUParticles3D")
		return null

# ============================================================================
# DAMAGE SYSTEM
# ============================================================================

func _create_damage_area() -> void:
	"""Create an Area3D with a SphereShape3D for damage detection."""
	_damage_area = Area3D.new()
	_damage_area.name = "DamageArea"
	_damage_area.collision_layer = 0  # Don't exist on any layer
	_damage_area.collision_mask = 4   # Detect layer 3 (enemy layer)
	_damage_area.monitorable = false
	
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = damage_radius
	shape.shape = sphere
	_damage_area.add_child(shape)
	add_child(_damage_area)

func _apply_damage() -> void:
	"""Deal damage to all enemies in the damage area."""
	var bodies := _damage_area.get_overlapping_bodies()
	for body in bodies:
		if damage_once and body in _damaged_enemies:
			continue
		
		if body.has_method("take_damage"):
			body.take_damage(damage)
			_damaged_enemies.append(body)
