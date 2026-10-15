extends Node
const AUTO_CREATE_LOBBY_ON_OFFICIAL_COOP_CONTINUE = true
const MAX_LOBBY_MEMBERS = 4
const LAN_PROTOCOL_VERSION = 2
const NETWORK_PROTOCOL_VERSION = "4.0.0"
const P2P_CHANNEL_MENU = 0
var _self_steam_id = "1"
var _online_role = "host"
var _session_active = true
var _pending_lan_join = false
var _lan_transport = null
var _lan_identity_challenges = {}
var _connection_by_peer_key = {}
var _peer_key_by_connection = {}
var _connections = {}
var _session_remote_peer_keys = []
var _host_known_remote_ids = []
var _kicked_departing_peer_keys = {}
var _rejected_peer_keys = {}
var _last_broadcast_selection_key = ""
var _sent_scene_transition_key_by_steam_id = {}
var _seen_client_hello_by_steam_id = {}
var frozen = false
var received_sender = ""
var failures = []
var welcomes = []
func is_online_session_active():
	return _session_active
func is_game_host():
	return _online_role == "host"
func _is_game_host():
	return is_game_host()
func get_self_steam_id():
	return _self_steam_id
func _get_slot_manager():
	return get_parent().get_node("BrotatoOnlineOnlinePlayerSlotManager")
func get_session_member_count():
	return max(1, _get_slot_manager().get_local_player_indices().size()) + _session_remote_peer_keys.size()
func _should_freeze_online_run_slots():
	return frozen
func _lock_online_run_slots(_reason):
	frozen = true
func _unlock_online_run_slots():
	frozen = false
func _remember_host_remote_id(key):
	if not _host_known_remote_ids.has(key):
		_host_known_remote_ids.append(key)
func _publish_session_metadata():
	pass
func _sync_host_coop_slots_from_lobby():
	pass
func get_lobby_state():
	return "shop"
func _get_wire_session_id():
	return "test-session"
func get_peer_display_name(key):
	return "Player " + key
func _drop_pending_p2p_sends_for_target(_key):
	pass
func _handle_client_host_disconnect(_reason):
	pass
func _handle_transport_welcome(_transport, _peer, message):
	welcomes.append(message)
func _handle_transport_session_id(_transport, _message):
	pass
func _handle_raw_p2p_packet(packet):
	received_sender = str(packet.sender)
	var message = parse_json(packet.bytes.get_string_from_utf8())
	if typeof(message) == TYPE_DICTIONARY and str(message.get("msg_type", "")) == "hello":
		_seen_client_hello_by_steam_id[received_sender] = true
func _ui_text(key):
	return key
func _show_join_failure(text):
	failures.append(text)
