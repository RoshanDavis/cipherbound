extends BaseSpellEffect
class_name HandSpellEffect
## Effect spawned near hands (Projectile, Slash).
## Projectiles fly forward dealing damage on contact.
## Slashes deal instant area damage.

const PARTICLES_CORE := preload("res://scenes/particles/projectile_core_particles.tscn")
const PARTICLES_TRAIL := preload("res://scenes/particles/projectile_trail_particles.tscn")
const PARTICLES_SLASH_HORIZ := preload("res://scenes/particles/horizontal_strike_particles.tscn")
const PARTICLES_SLASH_VERT := preload("res://scenes/particles/vertical_strike_particles.tscn")

enum HandEffectType { PROJECTILE, HORIZONTAL_SLASH, VERTICAL_SLASH }

@export var effect_type := HandEffectType.PROJECTILE
@export var projectile_speed := 18.0

var _direction := Vector3.FORWARD
var _is_projectile := false

func _ready() -> void:
	match effect_type:
		HandEffectType.PROJECTILE:
			lifetime = 3.0
			damage = 20.0
			damage_radius = 1.5
			damage_once = true
			_is_projectile = true
			add_particle_scene(PARTICLES_CORE)
			add_particle_scene(PARTICLES_TRAIL)
		HandEffectType.HORIZONTAL_SLASH:
			lifetime = 0.8
			damage = 12.0
			damage_radius = 3.0
			damage_once = true
			_is_projectile = false
			add_particle_scene(PARTICLES_SLASH_HORIZ)
		HandEffectType.VERTICAL_SLASH:
			lifetime = 0.8
			damage = 12.0
			damage_radius = 3.0
			damage_once = true
			_is_projectile = false
			add_particle_scene(PARTICLES_SLASH_VERT)
	
	super._ready()

func _on_update(delta: float) -> void:
	# Move projectile forward
	if _is_projectile:
		global_position += _direction * projectile_speed * delta

## Set direction for projectile travel
func set_direction(dir: Vector3) -> void:
	_direction = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	
	# Orient to face direction
	if _direction.length() > 0.01:
		look_at(global_position + _direction, Vector3.UP)
