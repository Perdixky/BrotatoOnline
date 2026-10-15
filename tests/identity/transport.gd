extends Node
var packets = []
var closed = []
func send_packet(peer, bytes, _channel, _reliable):
	packets.append({"peer": peer, "message": parse_json(bytes.get_string_from_utf8())})
	return true
func close_peer(peer):
	closed.append(peer)
func stop():
	pass
