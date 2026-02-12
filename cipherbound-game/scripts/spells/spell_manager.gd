extends Node
## Spell Manager - Singleton that handles spell effects and dispatch.
## This is an autoload that can be accessed from anywhere as SpellManager.
##
## To set up: Project Settings > Autoload > Add this script as "SpellManager"

# --- SPELL REGISTRY ---
## Maps cipher names to spell configurations
var spell_registry: Dictionary = {
	"air_blast": {
		"name": "Air Blast Jump",
		"emoji": "💨",
		"description": "A blast of air launches you skyward!"
	},
	"water": {
		"name": "Water Wave", 
		"emoji": "💧",
		"description": "Water flows around you!"
	},
	"shield": {
		"name": "Shield",
		"emoji": "🛡️",
		"description": "A magical barrier surrounds you!"
	},
	"lightning": {
		"name": "Throw Forward",
		"emoji": "⚡",
		"description": "A projectile thrown forward!"
	},
	"circle": {
		"name": "Mystic Orb",
		"emoji": "🔮",
		"description": "A mystical orb forms before you!"
	},
	"arrow_right": {
		"name": "Dash Right",
		"emoji": "➡️",
		"description": "Lateral dash to the right!",
		"is_movement": true
	},
	"arrow_left": {
		"name": "Dash Left",
		"emoji": "⬅️",
		"description": "Lateral dash to the left!",
		"is_movement": true
	},
	"swipe": {
		"name": "Swipe Horizontal",
		"emoji": "💨",
		"description": "Horizontal slash!"
	},
	"swipe_vertical": {
		"name": "Swipe Up",
		"emoji": "⬆️",
		"description": "Upward strike!"
	}
}

# --- SIGNALS ---
signal spell_cast_started(spell_name: String, origin: Vector3, direction: Vector3)
signal spell_cast_completed(spell_name: String)
signal spell_effect_spawned(spell_name: String, effect_node: Node)

func _ready() -> void:
	print("SpellManager initialized with ", spell_registry.size(), " spells")

## Main entry point for casting spells
func cast_spell(cipher_name: String, origin: Vector3, direction: Vector3) -> void:
	"""Cast a spell by cipher name from a given origin and direction."""
	if not spell_registry.has(cipher_name):
		push_warning("SpellManager: Unknown cipher '", cipher_name, "'")
		return
	
	var spell_info: Dictionary = spell_registry[cipher_name]
	print(spell_info["emoji"], " ", spell_info["description"])
	
	spell_cast_started.emit(cipher_name, origin, direction)
	
	# Dispatch to specific spell handler
	match cipher_name:
		"air_blast":
			_cast_air_blast(origin, direction)
		"water":
			_cast_water(origin, direction)
		"shield":
			_cast_shield(origin, direction)
		"lightning":
			_cast_lightning(origin, direction)
		"circle":
			_cast_circle(origin, direction)
		"arrow_right":
			_cast_dash_right(origin, direction)
		"arrow_left":
			_cast_dash_left(origin, direction)
		"swipe":
			_cast_swipe(origin, direction)
		"swipe_vertical":
			_cast_swipe_vertical(origin, direction)
		_:
			print("No effect implementation for: ", cipher_name)
	
	spell_cast_completed.emit(cipher_name)

## Get spell info by cipher name
func get_spell_info(cipher_name: String) -> Dictionary:
	return spell_registry.get(cipher_name, {})

## Check if a cipher has a registered spell
func has_spell(cipher_name: String) -> bool:
	return spell_registry.has(cipher_name)

## Register a new spell (for extensibility)
func register_spell(cipher_name: String, info: Dictionary) -> void:
	spell_registry[cipher_name] = info

# --- SPELL IMPLEMENTATIONS ---
# These are placeholder implementations. Replace with actual VFX/projectiles.

func _cast_air_blast(_origin: Vector3, _direction: Vector3) -> void:
	"""Air Blast - launches the player upward (handled by PlayerController)."""
	# The actual jump is handled by PlayerController's wind jump system.
	# This is here for spell registry completeness.
	pass

func _cast_water(_origin: Vector3, _direction: Vector3) -> void:
	"""Water spell - area effect around caster."""
	# TODO: Spawn water wave particles
	pass

func _cast_shield(_origin: Vector3, _direction: Vector3) -> void:
	"""Shield spell - defensive barrier."""
	# TODO: Spawn shield mesh/particles around player
	pass

func _cast_lightning(_origin: Vector3, _direction: Vector3) -> void:
	"""Lightning spell - instant raycast damage."""
	# TODO: Spawn lightning VFX along raycast
	pass

func _cast_circle(_origin: Vector3, _direction: Vector3) -> void:
	"""Mystic orb - utility/buff spell."""
	# TODO: Spawn orbiting orb
	pass

func _cast_dash_right(_origin: Vector3, _direction: Vector3) -> void:
	"""Dash right - lateral movement ability.
	Movement is handled by PlayerAnimator.dash_impulse signal.
	This function is for VFX only."""
	# TODO: Spawn dash trail particles
	pass

func _cast_dash_left(_origin: Vector3, _direction: Vector3) -> void:
	"""Dash left - lateral movement ability.
	Movement is handled by PlayerAnimator.dash_impulse signal.
	This function is for VFX only."""
	# TODO: Spawn dash trail particles
	pass

func _cast_swipe(_origin: Vector3, _direction: Vector3) -> void:
	"""Quick slash - melee attack."""
	# TODO: Spawn slash VFX, do area damage in front
	pass

func _cast_swipe_vertical(_origin: Vector3, _direction: Vector3) -> void:
	"""Vertical strike - overhead melee attack."""
	# TODO: Spawn vertical slash VFX
	pass
