extends BaseSpellEffect
class_name FootSpellEffect
## Effect spawned at player's feet (Jump, Dash).
## Loads particle scenes for upward burst.

const PARTICLES_AIR_BURST := preload("res://scenes/particles/air_burst_particles.tscn")
const PARTICLES_DASH := preload("res://scenes/particles/dash_trail_particles.tscn")

enum FootEffectType { AIR_BURST, DASH }

@export var effect_type := FootEffectType.AIR_BURST

func _ready() -> void:
	lifetime = 1.5
	
	match effect_type:
		FootEffectType.AIR_BURST:
			add_particle_scene(PARTICLES_AIR_BURST)
		FootEffectType.DASH:
			add_particle_scene(PARTICLES_DASH)
	
	super._ready()
