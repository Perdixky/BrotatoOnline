extends Node
enum PlayMode {SOLO, COOP}
var players_data = []
var start_wave_state = {}
func get_player_count() -> int:
	return players_data.size()
func get_player_character(_index):
	return null
