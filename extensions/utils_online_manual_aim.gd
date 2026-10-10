extends "res://singletons/utils.gd"

# Each machine's original manual-aim settings apply to its own character.
# Remote characters are automatic unless their owner opted in to sharing AND
# this machine has original manual aiming enabled.
func is_manual_aim(player_index: int) -> bool:
	var tree = get_tree()
	if tree == null or tree.root == null or not RunData.is_coop_run or not bool(tree.root.get_meta("brotato_online_session_active", false)):
		return .is_manual_aim(player_index)
	if player_index < 0 or player_index >= RunData.get_player_count():
		return false
	var manager = tree.root.get_node_or_null("ModLoader/six666-BrotatoOnline/BrotatoOnlineOnlineInputManager")
	if manager == null or not manager.has_method("is_local_player_index"):
		return .is_manual_aim(player_index)

	if manager.is_local_player_index(player_index):
		if ProgressData.settings.manual_aim_on_mouse_press or (on_console and ProgressData.settings.manual_aim):
			var mouse_pressed = not is_player_using_gamepad(player_index) and Input.is_mouse_button_pressed(BUTTON_LEFT)
			var gamepad_pressed = is_player_using_gamepad(player_index) and get_player_rjoy_vector(player_index).length_squared() > 0.05
			return mouse_pressed or gamepad_pressed
		return bool(ProgressData.settings.manual_aim)

	if not bool(ProgressData.settings.manual_aim) and not bool(ProgressData.settings.manual_aim_on_mouse_press):
		return false
	return bool(manager.is_remote_shared_manual_aim_active(player_index))
