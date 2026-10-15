extends Node
onready var root = get_tree().root
const Registry = preload("res://scripts/player_identity_registry.gd")
var failures = 0
var checks = 0
var mod = null
var session = null
var slots = null
var identity = null
var transport = null

func _ready():
	call_deferred("_run")

func check(value: bool, message: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _run():
	for filename in ["session_manager.gd", "online_player_slot_manager.gd", "player_removal_manager.gd"]:
		var script = load("res://scripts/" + filename)
		check(script != null and script.can_instance(), "whole production script compiles: " + filename)
	for path in ["res://mod_main.gd", "res://progress_extension.gd"]:
		var script = load(path)
		check(script != null and script.can_instance(), "production bootstrap/save extension compiles: " + path)
	_test_registry()
	var loader = Node.new()
	loader.name = "ModLoader"
	root.add_child(loader)
	mod = Node.new()
	mod.name = "six666-BrotatoOnline"
	loader.add_child(mod)
	session = load("res://session.gd").new()
	session.name = "BrotatoOnlineSessionManager"
	mod.add_child(session)
	slots = load("res://slots.gd").new()
	slots.name = "BrotatoOnlineOnlinePlayerSlotManager"
	mod.add_child(slots)
	identity = load("res://scripts/player_identity_manager.gd").new()
	identity.name = "BrotatoOnlinePlayerIdentityManager"
	mod.add_child(identity)
	identity.set_process(false)
	transport = load("res://transport.gd").new()
	mod.add_child(transport)
	session._lan_transport = transport
	var args = OS.get_cmdline_args()
	if "--preview" in args:
		_preview(args[args.find("--preview") + 1])
		return
	_test_reconnections()
	_test_resume_orders()
	_test_local_coop()
	_test_legacy()
	_test_lan()
	_test_transaction()
	_test_checkpoint_filter()
	_test_handshake_readiness()
	_test_new_run_credentials()
	yield(_test_loopback_transport(), "completed")
	if failures == 0:
		print("IDENTITY TESTS PASSED: ", checks, " checks")
	else:
		printerr("IDENTITY TESTS FAILED: ", failures, "/", checks)
	get_tree().quit(0 if failures == 0 else 1)

func _preview(output: String):
	var i18n = load("res://i18n.gd").new()
	i18n.name = "BrotatoOnlineI18n"
	mod.add_child(i18n)
	_reset()
	var scene = _resume({})
	if File.new().file_exists("res://preview_font.ttc"):
		var font = DynamicFont.new()
		var data = DynamicFontData.new()
		data.font_path = "res://preview_font.ttc"
		font.font_data = data
		font.size = 22
		var theme = Theme.new()
		theme.default_font = font
		identity._panel.theme = theme
	for index in range(2, 5):
		session._register_remote_connection(str(index), transport, index + 20)
	identity._update_panel()
	yield(get_tree().create_timer(0.3), "timeout")
	var screenshot = get_viewport().get_texture().get_data()
	screenshot.flip_y()
	var error = screenshot.save_png(output)
	check(error == OK, "UI screenshot exported")
	print("IDENTITY UI PREVIEW SAVED")
	get_tree().quit(0 if failures == 0 else 1)

func _owners(keys: Array) -> Array:
	var result = []
	for key in keys:
		result.append({"owner_id": str(key), "local_slot": 0})
	return result

func _test_registry():
	var registry = Registry.new()
	registry.assign(_owners(["1", "2", "3", "4"]))
	var state = registry.metadata()
	var restored = Registry.new()
	check(restored.load_metadata(parse_json(to_json(state)), 4), "JSON save round-trip")
	check(restored.index_for_owner("3") == 2, "ownership survives JSON numeric coercion")
	var slot_id = str(restored.slots[2].slot_id)
	restored.compact([0, 2, 3])
	check(restored.index_for_owner("3") == 1 and str(restored.slots[1].slot_id) == slot_id, "compaction keeps permanent slot ID")
	var invalid = state.duplicate(true)
	invalid.slots[1].owner_id = "1"
	check(not Registry.new().load_metadata(invalid, 4), "duplicate owners rejected")
	invalid = state.duplicate(true)
	invalid.slots[1].slot_id = invalid.slots[0].slot_id
	check(not Registry.new().load_metadata(invalid, 4), "duplicate slot IDs rejected")
	check(not Registry.new().load_metadata(state, 3), "count mismatch rejected")
	check(not Registry.new().load_metadata({}, 4), "old saves need explicit assignment")
	var lan = "lan:" + Registry.random_id()
	var token = Registry.random_id()
	registry.assign(_owners(["1", lan]), {lan: token.sha256_text()})
	check(registry.lan_proof_valid(lan, token), "LAN saved proof accepted")
	check(not registry.lan_proof_valid(lan, Registry.random_id()), "wrong LAN proof rejected")
	check(not token in to_json(registry.metadata()), "saved table has hashes, no private token")

func _reset():
	if get_tree().current_scene != null and get_tree().current_scene != self:
		get_tree().current_scene.free()
	get_tree().current_scene = null
	identity.reset_online_session_state()
	session._session_active = true
	session._online_role = "host"
	session.frozen = false
	session._connection_by_peer_key.clear()
	session._peer_key_by_connection.clear()
	session._connections.clear()
	session._session_remote_peer_keys.clear()
	session._host_known_remote_ids.clear()
	session._lan_identity_challenges.clear()
	session._seen_client_hello_by_steam_id.clear()
	slots._remote_steam_id_by_device.clear()
	slots._device_by_remote_steam_id.clear()
	slots._remote_devices.clear()
	CoopService.connected_players = [[7, 0]]
	RunData.players_data = ["gear1", "gear2", "gear3", "gear4"]
	RunData.start_wave_state = {}
	ProgressData.saved_run_state = {"has_run_state": true, "players_data": RunData.players_data.duplicate(), "shop_items": ["shop1", "shop2", "shop3", "shop4"]}
	ProgressData.last_saved_run_state = ProgressData.saved_run_state.duplicate(true)
	transport.closed.clear()
	transport.packets.clear()
	session.welcomes.clear()

func _resume(metadata: Dictionary):
	if not metadata.empty():
		ProgressData.saved_run_state[Registry.SAVE_KEY] = metadata
	var scene = load("res://resume.gd").new()
	scene.filename = "res://ui/menus/shop/coop_resume.tscn"
	root.add_child(scene)
	get_tree().current_scene = scene
	identity.prepare_resume_if_needed()
	return scene

func _test_reconnections():
	_reset()
	check(session._register_remote_connection("2", transport, 21), "first owner admitted")
	check(session._register_remote_connection("3", transport, 31), "second owner admitted")
	session._on_transport_peer_disconnected(transport, 21)
	session._on_transport_peer_disconnected(transport, 31)
	session.frozen = true
	check(session._register_remote_connection("3", transport, 32), "second owner reconnects first during battle")
	check(session._session_remote_peer_keys == ["2", "3"], "reconnect cannot overwrite first absent owner")
	check(session._register_remote_connection("3", transport, 32), "repeated connection registration is idempotent")
	check(not session._register_remote_connection("3", transport, 33), "duplicate live owner rejected")
	check(not session._register_remote_connection("4", transport, 41), "stranger cannot take disconnected battle slot")
	check(session._register_remote_connection("2", transport, 22), "first owner returns to its own slot")
	# An old transport callback cannot remove a newer connection.
	session._peer_key_by_connection[session._connection_lookup_key(transport, 21)] = "2"
	session._on_transport_peer_disconnected(transport, 21)
	check(session._connection_by_peer_key["2"].peer == 22, "stale disconnect preserves new connection")
	session.received_sender = ""
	session._on_transport_packet_received(transport, 41, to_json({"sender_steam_id": "2"}).to_utf8(), 0)
	check(session.received_sender == "", "unregistered connection cannot spoof another owner's sender")
	session._on_transport_packet_received(transport, 32, to_json({"sender_steam_id": "2"}).to_utf8(), 0)
	check(session.received_sender == "3", "registered connection uses actual sender instead of claimed owner")

func _test_resume_orders():
	for order in [["2", "3", "4"], ["2", "4", "3"], ["3", "2", "4"], ["3", "4", "2"], ["4", "2", "3"], ["4", "3", "2"]]:
		_reset()
		var registry = Registry.new()
		registry.assign(_owners(["1", "2", "3", "4"]))
		var scene = _resume(registry.metadata())
		for position in range(order.size()):
			check(session._register_remote_connection(order[position], transport, position + 20), "resume admission " + str(order))
			session._seen_client_hello_by_steam_id[order[position]] = true
			CoopService.emit_signal("connected_players_updated", CoopService.connected_players)
			identity._try_commit(false)
			if position < 2:
				check(not scene.finished and identity.is_resume_pending(), "wait for absent owners " + str(order))
				check(not session._official_continue_players_ready(), "offline owner never counted ready")
		check(scene.finished and not identity.is_resume_pending(), "complete resume " + str(order))
		check(scene.advance_count == 2, "vanilla progression runs once after full commit")
		for index in range(1, 4):
			check(slots.get_player_index_for_steam_id(str(index + 1)) == index, "saved index preserved " + str(order))
		check(RunData.players_data == ["gear1", "gear2", "gear3", "gear4"], "gear stays in saved slots")
		check(ProgressData.saved_run_state.shop_items == ["shop1", "shop2", "shop3", "shop4"], "shop data stays in saved slots")
		check(session._session_remote_peer_keys == ["2", "3", "4"], "transport bindings follow committed order")

func _test_local_coop():
	_reset()
	var registry = Registry.new()
	registry.assign([{"owner_id": "1", "local_slot": 0}, {"owner_id": "2", "local_slot": 0}, {"owner_id": "1", "local_slot": 1}, {"owner_id": "3", "local_slot": 0}])
	var scene = _resume(registry.metadata())
	session._register_remote_connection("3", transport, 30)
	session._register_remote_connection("2", transport, 20)
	session._seen_client_hello_by_steam_id = {"2": true, "3": true}
	identity._try_commit(false)
	check(not scene.finished, "missing second host-local input blocks resume")
	CoopService.connected_players.append([6, 1])
	CoopService.emit_signal("connected_players_updated", CoopService.connected_players)
	identity._try_commit(false)
	check(scene.finished and CoopService.connected_players[2] == [6, 1], "host local ordinal maps to saved nonadjacent slot")
	check(slots.get_player_index_for_steam_id("2") == 1 and slots.get_player_index_for_steam_id("3") == 3, "mixed local/online ownership restored")

func _test_legacy():
	_reset()
	var scene = _resume({})
	for index in range(2, 5):
		session._register_remote_connection(str(index), transport, index + 20)
		session._seen_client_hello_by_steam_id[str(index)] = true
	identity._update_panel()
	identity._try_commit(false)
	check(not scene.finished and identity._manual, "legacy save never guesses join-order ownership")
	for index in range(identity._choices.size()):
		identity._choices[index].select(index + 1)
	identity._confirm_assignment()
	check(scene.finished and ProgressData.saved_run_state.has(Registry.SAVE_KEY), "host confirmation migrates old save")
	var migrated = Registry.new()
	check(migrated.load_metadata(ProgressData.saved_run_state[Registry.SAVE_KEY], 4), "migrated table valid on next resume")

func _test_lan():
	_reset()
	var install = Registry.random_id()
	var token = Registry.random_id()
	var owner = "lan:" + install
	var registry = Registry.new()
	registry.assign(_owners(["1", owner, "3", "4"]), {owner: token.sha256_text()})
	_resume(registry.metadata())
	check(identity.accept_lan_identity(install, token), "saved LAN identity accepts its token")
	check(not identity.accept_lan_identity(install, Registry.random_id()), "same installation with wrong proof denied")
	check(identity.client_identity_for_run(registry.run_id).resume_token == identity.client_identity_for_run(registry.run_id).resume_token, "client proof survives retry")
	session._on_transport_peer_connected(transport, 100)
	var request = transport.packets.back().message
	check(request.msg_type == "transport_identity_request" and request.run_id == registry.run_id, "LAN connection challenged for saved run")
	var reply = {"msg_type": "transport_identity", "installation_id": install, "resume_token": token, "run_id": registry.run_id, "protocol_version": 2}
	session._handle_transport_identity(transport, 100, reply)
	check(session._connection_by_peer_key.has(owner), "verified LAN owner uses stable key")
	session._on_transport_peer_disconnected(transport, 100)
	session._on_transport_peer_connected(transport, 200)
	session._handle_transport_identity(transport, 200, reply)
	check(session._connection_by_peer_key[owner].peer == 200 and session._session_remote_peer_keys == [owner], "changed ENet ID reconnects to same owner")
	session._online_role = "client"
	session._pending_lan_join = false
	transport.packets.clear()
	session._handle_transport_identity(transport, 1, {"msg_type": "transport_identity_request", "run_id": registry.run_id, "protocol_version": 2, "mod_version": "4.0.0"})
	check(not transport.packets.empty() and transport.packets.back().message.msg_type == "transport_identity", "automatic LAN reconnect answers challenge while already active")
	session._online_role = "host"

func _test_transaction():
	_reset()
	var before = CoopService.connected_players.duplicate(true)
	check(not slots.apply_resume_identity_layout([{"peer_key": "", "local_slot": 0}, {"peer_key": "2"}, {"peer_key": "2"}, {"peer_key": "3"}]), "duplicate layout rejected")
	check(CoopService.connected_players == before and slots._device_by_remote_steam_id.empty(), "failed commit has no partial topology")
	identity.registry.assign(_owners(["1", "2", "3", "4"]))
	ProgressData.saved_run_state[Registry.SAVE_KEY] = identity.registry.metadata()
	RunData.start_wave_state = ProgressData.saved_run_state.duplicate(true)
	var old_slot_id = identity.registry.slots[2].slot_id
	RunData.players_data = ["gear1", "gear3", "gear4"]
	ProgressData.saved_run_state.players_data = RunData.players_data.duplicate()
	RunData.start_wave_state.players_data = RunData.players_data.duplicate()
	identity.compact_slots([0, 2, 3])
	check(identity.registry.slots[1].slot_id == old_slot_id, "removal keeps durable slot identity")
	check(RunData.start_wave_state[Registry.SAVE_KEY].slots.size() == 3, "retry cannot resurrect removed owner")

func _test_checkpoint_filter():
	_reset()
	var removal = load("res://scripts/player_removal_manager.gd").new()
	mod.add_child(removal)
	removal.set_process(false)
	removal._affects_saved_run = true
	removal._removed = {1: "2"}
	identity.registry.assign(_owners(["1", "2", "3", "4"]))
	var state = identity.attach_saved_identity(ProgressData.saved_run_state.duplicate(true))
	var filtered = removal.filter_saved_state(state)
	check(filtered.players_data == ["gear1", "gear3", "gear4"], "checkpoint removal filters character data")
	check(filtered[Registry.SAVE_KEY].slots[1].owner_id == "3", "checkpoint removal filters ownership in same positions")
	check(filtered[Registry.SAVE_KEY].slots[1].slot_id == state[Registry.SAVE_KEY].slots[2].slot_id, "checkpoint removal retains slot ID")
	var again = removal.filter_saved_state(filtered)
	check(again.players_data == filtered.players_data and again[Registry.SAVE_KEY].slots.size() == 3, "repeated checkpoint filtering is idempotent")
	var freshly_filtered = ProgressData.saved_run_state.duplicate(true)
	freshly_filtered.players_data = ["gear1", "gear3", "gear4"]
	freshly_filtered.bo_roster_slots = [0, 2, 3]
	freshly_filtered = identity.attach_saved_identity(freshly_filtered)
	check(freshly_filtered[Registry.SAVE_KEY].slots[1].owner_id == "3", "fresh save metadata honors filtered indices")
	removal.free()

func _test_handshake_readiness():
	_reset()
	RunData.players_data = ["gear1", "gear2"]
	ProgressData.saved_run_state.players_data = RunData.players_data.duplicate()
	var registry = Registry.new()
	registry.assign(_owners(["1", "2"]))
	var scene = _resume(registry.metadata())
	check(not session._register_remote_connection("3", transport, 30), "stranger cannot consume saved owner's waiting seat")
	session._register_remote_connection("2", transport, 20)
	identity._try_commit(false)
	check(not scene.finished, "Steam membership before hello does not advance resume")
	session._seen_client_hello_by_steam_id["2"] = true
	identity._try_commit(false)
	check(scene.finished, "actual client hello permits commit")
	check(session.frozen, "committed topology locked before deferred shop transition")

func _test_new_run_credentials():
	_reset()
	var install = Registry.random_id()
	var owner = "lan:" + install
	var old_token = Registry.random_id()
	identity.registry.run_id = Registry.random_id()
	var old_run = identity.registry.run_id
	identity._lan_hashes[owner] = old_token.sha256_text()
	session._register_remote_connection(owner, transport, 50)
	var selection = Control.new()
	selection.filename = "res://ui/menus/character_selection.tscn"
	root.add_child(selection)
	get_tree().current_scene = selection
	identity._reset_for_new_selection()
	var next_run = identity.registry.run_id
	check(next_run != old_run, "same-room new run gets fresh run ID")
	check(transport.packets.back().message.run_id == next_run, "existing LAN connection challenged for new run")
	var new_token = Registry.random_id()
	var reply = {"msg_type": "transport_identity", "installation_id": install, "resume_token": new_token, "run_id": next_run, "protocol_version": 2}
	session._handle_transport_identity(transport, 50, reply)
	check(identity._lan_hashes.get(owner, "") == new_token.sha256_text(), "existing authenticated connection rotates per-run proof")
	check(session._session_remote_peer_keys == [owner], "credential rotation does not add or move a player")
	var packet_count = transport.packets.size()
	reply.run_id = old_run
	session._handle_transport_identity(transport, 50, reply)
	check(transport.packets.size() == packet_count and transport.closed.empty(), "delayed old-run response ignored without disconnecting")
	var credential = identity.client_identity_for_run(next_run)
	var reloaded = load("res://scripts/player_identity_manager.gd").new()
	mod.add_child(reloaded)
	reloaded.set_process(false)
	var restored = reloaded.client_identity_for_run(next_run)
	check(credential.resume_token == restored.resume_token and credential.installation_id == restored.installation_id, "client identity and proof persist across manager restart")
	reloaded.free()

func _test_loopback_transport():
	_reset()
	RunData.players_data = ["gear1", "gear2"]
	ProgressData.saved_run_state.players_data = RunData.players_data.duplicate()
	var registry = Registry.new()
	registry.run_id = Registry.random_id()
	var credential = identity.client_identity_for_run(registry.run_id)
	var owner = "lan:" + str(credential.installation_id)
	registry.assign(_owners(["1", owner]), {owner: str(credential.resume_token).sha256_text()})
	var scene = _resume(registry.metadata())
	var host_transport = load("res://scripts/lan_transport.gd").new()
	mod.add_child(host_transport)
	session._lan_transport = host_transport
	_bind_transport(host_transport, session)
	var client_group = Node.new()
	root.add_child(client_group)
	var client_session = load("res://session.gd").new()
	client_session.name = "BrotatoOnlineSessionManager"
	client_session._online_role = "client"
	client_session._pending_lan_join = true
	client_group.add_child(client_session)
	var client_identity = load("res://scripts/player_identity_manager.gd").new()
	client_identity.name = "BrotatoOnlinePlayerIdentityManager"
	client_group.add_child(client_identity)
	client_identity.set_process(false)
	var client_transport = load("res://scripts/lan_transport.gd").new()
	client_group.add_child(client_transport)
	client_session._lan_transport = client_transport
	_bind_transport(client_transport, client_session)
	var port = 29000 + int(OS.get_ticks_usec() % 1000)
	check(host_transport.start_host(port) == OK, "loopback ENet host starts")
	check(client_transport.start_client("127.0.0.1", port) == OK, "loopback ENet client starts")
	var deadline = OS.get_ticks_msec() + 3500
	while client_session.welcomes.empty() and OS.get_ticks_msec() < deadline:
		yield(get_tree().create_timer(0.02), "timeout")
	check(not client_session.welcomes.empty() and bool(client_session.welcomes.back().accepted), "real ENet identity challenge/welcome completes")
	check(session._connection_by_peer_key.has(owner), "real packet sender registered under persistent owner")
	if not session._connection_by_peer_key.has(owner):
		client_transport.stop()
		host_transport.stop()
		client_group.free()
		host_transport.free()
		session._lan_transport = transport
		return
	var old_peer = session._connection_by_peer_key[owner].peer
	client_transport.send_packet(1, to_json({"msg_type": "hello", "sender_steam_id": owner}).to_utf8(), 0, true)
	deadline = OS.get_ticks_msec() + 1500
	while not session._seen_client_hello_by_steam_id.has(owner) and OS.get_ticks_msec() < deadline:
		yield(get_tree().create_timer(0.02), "timeout")
	identity._try_commit(false)
	check(scene.finished and slots.get_player_index_for_steam_id(owner) == 1, "real ENet resume commits correct saved character")
	client_transport.stop()
	yield(get_tree().create_timer(0.15), "timeout")
	client_session.welcomes.clear()
	client_transport.start_client("127.0.0.1", port)
	deadline = OS.get_ticks_msec() + 3500
	while client_session.welcomes.empty() and OS.get_ticks_msec() < deadline:
		yield(get_tree().create_timer(0.02), "timeout")
	check(not client_session.welcomes.empty() and bool(client_session.welcomes.back().accepted), "real ENet reconnect validates persisted proof")
	check(session._connection_by_peer_key.has(owner) and session._connection_by_peer_key[owner].peer != old_peer, "real reconnect receives a different ENet peer ID")
	check(session._session_remote_peer_keys == [owner] and slots.get_player_index_for_steam_id(owner) == 1, "real reconnect keeps one owner and the same saved slot")
	client_transport.stop()
	host_transport.stop()
	client_group.free()
	host_transport.free()
	session._lan_transport = transport

func _bind_transport(endpoint: Node, target: Node):
	endpoint.connect("peer_connected", target, "_on_transport_peer_connected")
	endpoint.connect("peer_disconnected", target, "_on_transport_peer_disconnected")
	endpoint.connect("packet_received", target, "_on_transport_packet_received")
