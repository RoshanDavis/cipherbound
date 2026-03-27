extends BaseSpellEffect
class_name GroundSpellEffect
## Effect spawned on ground in front of player (Smash Ground).
## Powerful area damage with debris and shockwave particles.

const PARTICLES_SLAM := preload("res://scenes/particles/ground_slam_particles.tscn")
const PARTICLES_WAVE := preload("res://scenes/particles/ground_wave_particles.tscn")

func _ready() -> void:
	lifetime = 2.0
	damage = 25.0
	damage_radius = 4.0
	
	add_particle_scene(PARTICLES_SLAM)
	add_particle_scene(PARTICLES_WAVE)
	
	super._ready()
