extends BaseSpellEffect
class_name GroundSpellEffect
## Effect spawned on ground in front of player (Smash Ground).
## Loads particle scenes for debris explosion and wave.

const PARTICLES_SLAM := preload("res://scenes/particles/ground_slam_particles.tscn")
const PARTICLES_WAVE := preload("res://scenes/particles/ground_wave_particles.tscn")

func _ready() -> void:
	lifetime = 2.0
	
	# Debris particles
	add_particle_scene(PARTICLES_SLAM)
	
	# Wave particles
	add_particle_scene(PARTICLES_WAVE)
	
	super._ready()
