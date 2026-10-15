extends "res://ui/menus/shop/coop_resume.gd"


func _ready() -> void:
	var identity = _identity_manager()
	if identity != null:
		identity.attach_resume_scene(self)
	# Godot 3 calls the inherited lifecycle callback automatically.


func _on_connected_players_updated(connected_players: Array) -> void:
	var identity = _identity_manager()
	if identity != null and identity.guards_resume(self):
		return
	._on_connected_players_updated(connected_players)


func identity_resume_committed() -> void:
	# The character data is already loaded. Advance only after the whole input
	# topology has been validated and installed in its saved order.
	_players_to_join.clear()
	_setup_next_player()


func identity_resume_offline() -> void:
	# Inputs may already have joined while online creation was in flight. Rebuild
	# vanilla's pending queue before enabling its normal join callbacks again.
	_players_to_join.clear()
	for index in range(CoopService.connected_players.size(), RunData.get_player_count()):
		_players_to_join.append(index)
	CoopService.listening_for_inputs = true
	_setup_next_player()


func _identity_manager():
	return get_node_or_null("/root/ModLoader/six666-BrotatoOnline/BrotatoOnlinePlayerIdentityManager")
