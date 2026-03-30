extends Node
## Spell Manager - Singleton that handles spell effects and dispatch.
## This is an autoload that can be accessed from anywhere as SpellManager.
##
## To set up: Project Settings > Autoload > Add this script as "SpellManager"

# --- EFFECT SCRIPTS ---
# Effects are created programmatically - they load their own particle scenes
const FootSpellEffectScript := preload("res://scripts/spells/effects/foot_effect.gd")
const GroundSpellEffectScript := preload("res://scripts/spells/effects/ground_effect.gd")
const BodySpellEffectScript := preload("res://scripts/spells/effects/body_effect.gd")
const HandSpellEffectScript := preload("res://scripts/spells/effects/hand_effect.gd")

## Spawn location types
enum SpawnLocation { FEET, GROUND_FRONT, BODY_CENTER, HAND }

## Effect types for hand effects
enum HandEffect { PROJECTILE, HORIZONTAL_SLASH, VERTICAL_SLASH }

## Effect types for foot effects
enum FootEffect { AIR_BURST, DASH }

# --- SPELL REGISTRY ---
## Maps cipher names to spell configurations
var spell_registry: Dictionary = {
	"air_jump": {
		"name": "Air Jump",
		"emoji": "💨",
		"description": "Jump into the air with a wind burst!",
		"spawn_location": SpawnLocation.FEET,
		"effect_type": FootEffect.AIR_BURST
	},
	"ground_smash": {
		"name": "Ground Smash", 
		"emoji": "💥",
		"description": "Smash the ground with force!",
		"spawn_location": SpawnLocation.GROUND_FRONT,
		"effect_type": null
	},
	"aoe_attack_sq": {
		"name": "AOE Attack",
		"emoji": "🛡️",
		"description": "Area of effect blast!",
		"spawn_location": SpawnLocation.BODY_CENTER,
		"effect_type": null
	},
	"aoe_attack": {
		"name": "AOE Attack",
		"emoji": "🛡️",
		"description": "Area of effect blast!",
		"spawn_location": SpawnLocation.BODY_CENTER,
		"effect_type": null
	},
	"fireball": {
		"name": "Fireball",
		"emoji": "🔥",
		"description": "A fireball shoots forward!",
		"spawn_location": SpawnLocation.HAND,
		"effect_type": HandEffect.PROJECTILE
	},
	"dash_right": {
		"name": "Dash Right",
		"emoji": "➡️",
		"description": "Lateral dash to the right!",
		"is_movement": true,
		"spawn_location": SpawnLocation.FEET,
		"effect_type": FootEffect.DASH
	},
	"dash_left": {
		"name": "Dash Left",
		"emoji": "⬅️",
		"description": "Lateral dash to the left!",
		"is_movement": true,
		"spawn_location": SpawnLocation.FEET,
		"effect_type": FootEffect.DASH
	},
	"horizontal_strike": {
		"name": "Horizontal Strike",
		"emoji": "💨",
		"description": "Horizontal slash!",
		"spawn_location": SpawnLocation.HAND,
		"effect_type": HandEffect.HORIZONTAL_SLASH
	},
	"vertical_strike": {
		"name": "Vertical Strike",
		"emoji": "⬆️",
		"description": "Upward strike!",
		"spawn_location": SpawnLocation.HAND,
		"effect_type": HandEffect.VERTICAL_SLASH
	}
}

## Reference to the current player (set by PlayerController)
var _player: Node3D = null
var _spawn_points: Dictionary = {}  # SpawnLocation -> Marker3D

# --- SIGNALS ---
signal spell_cast_started(spell_name: String, origin: Vector3, direction: Vector3)
signal spell_cast_completed(spell_name: String)
signal spell_effect_spawned(spell_name: String, effect_node: Node)

func _ready() -> void:
	print("SpellManager initialized with ", spell_registry.size(), " spells")

## Register the player and its spawn points
func register_player(player: Node3D, spawn_points: Dictionary) -> void:
	"""Register the player and spawn point markers.
	spawn_points should be: { SpawnLocation.FEET: Marker3D, ... }"""
	_player = player
	_spawn_points = spawn_points
	print("SpellManager: Player registered with ", spawn_points.size(), " spawn points")

## Main entry point for casting spells
func cast_spell(cipher_name: String, origin: Vector3, direction: Vector3) -> void:
	"""Cast a spell by cipher name from a given origin and direction."""
	if not spell_registry.has(cipher_name):
		push_warning("SpellManager: Unknown cipher '", cipher_name, "'")
		return
	
	var spell_info: Dictionary = spell_registry[cipher_name]
	print(spell_info["emoji"], " ", spell_info["description"])
	
	spell_cast_started.emit(cipher_name, origin, direction)
	
	# Spawn the visual effect
	_spawn_effect(cipher_name, origin, direction)
	
	spell_cast_completed.emit(cipher_name)

func _spawn_effect(cipher_name: String, fallback_origin: Vector3, direction: Vector3) -> void:
	"""Spawn the visual effect for a spell at the appropriate location."""
	var spell_info: Dictionary = spell_registry.get(cipher_name, {})
	if spell_info.is_empty():
		return
	
	# Determine spawn position
	var spawn_location: SpawnLocation = spell_info.get("spawn_location", SpawnLocation.HAND)
	var spawn_pos := _get_spawn_position(spawn_location, fallback_origin, direction)
	var effect_type = spell_info.get("effect_type")
	
	# Create effect based on spawn location
	var effect: Node3D = _create_effect(spawn_location, effect_type)
	if not effect:
		push_warning("SpellManager: Failed to create effect for ", cipher_name)
		return
	
	# Add to scene tree
	var effects_parent := get_tree().root.get_node_or_null("Game/Effects")
	if effects_parent:
		effects_parent.add_child(effect)
	else:
		get_tree().root.add_child(effect)
	
	# Position and orient
	effect.global_position = spawn_pos
	
	# Orient projectiles/slashes toward direction
	if spawn_location == SpawnLocation.HAND and direction.length() > 0.01:
		if effect.has_method("set_direction"):
			effect.set_direction(direction)
		else:
			effect.look_at(spawn_pos + direction, Vector3.UP)
	
	spell_effect_spawned.emit(cipher_name, effect)

func _create_effect(location: SpawnLocation, effect_type) -> Node3D:
	"""Create the appropriate effect node based on spawn location."""
	var effect: Node3D = null
	
	match location:
		SpawnLocation.FEET:
			effect = Node3D.new()
			effect.set_script(FootSpellEffectScript)
			if effect_type != null:
				effect.effect_type = effect_type
		SpawnLocation.GROUND_FRONT:
			effect = Node3D.new()
			effect.set_script(GroundSpellEffectScript)
		SpawnLocation.BODY_CENTER:
			effect = Node3D.new()
			effect.set_script(BodySpellEffectScript)
		SpawnLocation.HAND:
			effect = Node3D.new()
			effect.set_script(HandSpellEffectScript)
			if effect_type != null:
				effect.effect_type = effect_type
	
	return effect

func _get_spawn_position(location: SpawnLocation, fallback: Vector3, _direction: Vector3) -> Vector3:
	"""Get the world position for a spawn location."""
	# Try to use registered spawn points first
	if _spawn_points.has(location):
		var marker: Marker3D = _spawn_points[location]
		if marker and is_instance_valid(marker):
			return marker.global_position
	
	# Fallback calculations based on player position
	if _player and is_instance_valid(_player):
		var player_pos := _player.global_position
		
		match location:
			SpawnLocation.FEET:
				return player_pos  # Ground level
			SpawnLocation.GROUND_FRONT:
				# 1.5m in front of player at ground level
				var forward := -_player.global_transform.basis.z
				return player_pos + forward * 1.5
			SpawnLocation.BODY_CENTER:
				return player_pos + Vector3(0, 1.0, 0)  # Chest height
			SpawnLocation.HAND:
				# Use fallback origin (usually SpellOrigin marker)
				return fallback
	
	return fallback

## Get spell info by cipher name
func get_spell_info(cipher_name: String) -> Dictionary:
	return spell_registry.get(cipher_name, {})

## Check if a cipher has a registered spell
func has_spell(cipher_name: String) -> bool:
	return spell_registry.has(cipher_name)

## Register a new spell (for extensibility)
func register_spell(cipher_name: String, info: Dictionary) -> void:
	spell_registry[cipher_name] = info
