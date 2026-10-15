extends Node
const REMOTE_PLACEHOLDER_DEVICE_IDS = [1, 2, 3, 4, 5]
const REMOTE_PLACEHOLDER_PLAYER_TYPE = 1
var _remote_steam_id_by_device = {}
var _device_by_remote_steam_id = {}
var _remote_devices = []
var _local_mirrored_player_index = -1
var _local_mirrored_steam_id = ""
var _mirrored_connected_players = []
var _last_observed_local_layout_key = ""
func _is_slot_mutation_locked():
	return false
func _get_connected_local_gamepad_remapped_devices():
	return []
func _build_local_layout_key():
	return ""
func _get_player_index_for_device(device):
	for index in range(CoopService.connected_players.size()):
		if int(CoopService.connected_players[index][0]) == device:
			return index
	return -1
func _ensure_host_player_joined():
	if CoopService.connected_players.empty():
		CoopService.connected_players.append([7, 0])
		CoopService.emit_signal("connected_players_updated", CoopService.connected_players)
