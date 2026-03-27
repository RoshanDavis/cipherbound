extends Node3D
class_name BaseSpellEffect
## Base class for all spell visual effects.
## Simple particle-only system with automatic cleanup.

signal effect_finished

## How long before auto-cleanup (should be >= longest particle lifetime)
@export var lifetime := 2.0

var _elapsed := 0.0
var _particles: Array[GPUParticles3D] = []

func _ready() -> void:
	# Collect all particle children added by subclass
	_collect_particles()
	# Start the effect
	play()

func _collect_particles() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			_particles.append(child)

func _process(delta: float) -> void:
	_elapsed += delta
	_on_update(delta)
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
