extends BaseSpellEffect
class_name FootSpellEffect
## Effect spawned at player's feet (Jump, Dash).
## Creates air burst particles with area damage.

const PARTICLES_AIR_BURST := preload("res://scenes/particles/air_burst_particles.tscn")
const PARTICLES_DASH := preload("res://scenes/particles/dash_trail_particles.tscn")

enum FootEffectType { AIR_BURST, DASH }

@export var effect_type := FootEffectType.AIR_BURST

func _ready() -> void:
	match effect_type:
		FootEffectType.AIR_BURST:
			lifetime = 1.5
			damage = 15.0
			damage_radius = 3.0
			add_particle_scene(PARTICLES_AIR_BURST)
		FootEffectType.DASH:
			lifetime = 1.0
			damage = 10.0
			damage_radius = 2.0
			add_particle_scene(PARTICLES_DASH)
	
	super._ready()
