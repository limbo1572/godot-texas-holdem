extends Node
## Autoload "Net". ENet connection layer + lobby player registry.
## Host is always peer 1 and is the single source of truth.

signal players_changed
signal connected_as_client
signal join_failed(reason: String)
signal host_left
signal peer_left(peer_id: int, player_name: String)

const MAX_CLIENTS := 5 ## 6 seats total including host

var players: Dictionary = {} ## peer_id -> display name
var is_host: bool = false
var active: bool = false
var last_error: String = "" ## shown by lobby after returning from a dropped session
var suppress_rpc: bool = false ## set by in-process unit tests (no matching remote node paths)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func create_server(port: int) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return {"ok": false, "error": "Cannot host on port %d (%s) — port busy or invalid?" % [port, error_string(err)]}
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	players = {1: "Player 1 (host)"}
	players_changed.emit()
	print("[net] hosting on port %d" % port)
	return {"ok": true, "error": ""}


func join_server(ip: String, port: int) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		return {"ok": false, "error": "Cannot start client (%s)" % error_string(err)}
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	print("[net] connecting to %s:%d ..." % [ip, port])
	return {"ok": true, "error": ""}


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	is_host = false
	active = false
	players_changed.emit()


func _on_peer_connected(id: int) -> void:
	print("[net] peer %d connected" % id)
	if is_host:
		players[id] = "Player %d" % id
		_broadcast_players()


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d disconnected" % id)
	if is_host and players.has(id):
		var player_name: String = players[id]
		players.erase(id)
		_broadcast_players()
		peer_left.emit(id, player_name)


func _on_connected_to_server() -> void:
	print("[net] connected to host, my peer id = %d" % multiplayer.get_unique_id())
	connected_as_client.emit()


func _on_connection_failed() -> void:
	print("[net] connection failed")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	join_failed.emit("Could not reach host (refused or timed out). Check IP:port.")


func _on_server_disconnected() -> void:
	print("[net] host disconnected")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	active = false
	last_error = "Host disconnected."
	players_changed.emit()
	host_left.emit()


func _broadcast_players() -> void:
	players_changed.emit()
	if not suppress_rpc:
		sync_players.rpc(players)


@rpc("authority", "call_remote", "reliable")
func sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()
