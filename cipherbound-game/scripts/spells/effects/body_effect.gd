extends BaseSpellEffect
class_name BodySpellEffect
## Effect expanding from player body (Shield).
## Sustained protective burst with continuous damage to nearby enemies.

const PARTICLES_BURST := preload("res://scenes/particles/shield_burst_particles.tscn")
const PARTICLES_SUSTAIN := preload("res://scenes/particles/shield_sustain_particles.tscn")

@export var shield_duration := 3.0

var _sustain_particles: GPUParticles3D

func _ready() -> void:
	lifetime = shield_duration + 1.0
	damage = 5.0
	damage_radius = 3.0
	damage_once = false  # Continuous damage while shield is active
	
	# Initial burst
	add_particle_scene(PARTICLES_BURST)
	
	# Sustained particles during shield
	_sustain_particles = add_particle_scene(PARTICLES_SUSTAIN)
	
	super._ready()
	
	# Stop sustain particles after shield duration
	_stop_sustain_after_duration()

func _stop_sustain_after_duration() -> void:
	await get_tree().create_timer(shield_duration).timeout
	if is_instance_valid(_sustain_particles):
		_sustain_particles.emitting = false
