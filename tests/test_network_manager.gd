extends SceneTree
## Unit test for network_manager.gd: server create, port conflict, client
## connect over localhost, peer_connected firing, peer counts.
## Uses two MultiplayerAPI branches in one process (RPC sync is suppressed
## because node paths differ between branches; RPCs are covered by the E2E test).

const PORT := 8971

var _passed := 0
var _failed := 0
var _server_peer_events: Array = []
var _client_connected_events: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	## Nodes only enter the tree once the main loop starts; wait one frame
	## so node.multiplayer resolves and _ready callbacks fire.
	await process_frame
	print("=== test_network_manager ===")
	var nm_script := load("res://scripts/network_manager.gd")

	var server_root := Node.new()
	server_root.name = "S"
	root.add_child(server_root)
	set_multiplayer(MultiplayerAPI.create_default_interface(), "/root/S")

	var client_root := Node.new()
	client_root.name = "C"
	root.add_child(client_root)
	set_multiplayer(MultiplayerAPI.create_default_interface(), "/root/C")

	var extra_root := Node.new()
	extra_root.name = "X"
	root.add_child(extra_root)
	set_multiplayer(MultiplayerAPI.create_default_interface(), "/root/X")

	var server = nm_script.new()
	server.suppress_rpc = true
	server_root.add_child(server)
	var client = nm_script.new()
	client.suppress_rpc = true
	client_root.add_child(client)
	var extra = nm_script.new()
	extra.suppress_rpc = true
	extra_root.add_child(extra)

	server.multiplayer.peer_connected.connect(func(id: int) -> void: _server_peer_events.append(id))
	client.multiplayer.connected_to_server.connect(func() -> void: _client_connected_events.append(true))

	# 1. Host on free port
	var host_result: Dictionary = server.create_server(PORT)
	_check(host_result.ok, "create_server on free port succeeds")
	_check(server.is_host and server.active, "host flags set")
	_check(server.players.size() == 1 and server.players.has(1), "host registers itself as peer 1")

	# 2. Same port again -> must fail gracefully
	var busy_result: Dictionary = extra.create_server(PORT)
	_check(not busy_result.ok, "create_server on busy port fails gracefully")
	_check(busy_result.error != "", "busy port returns readable error: %s" % busy_result.error)

	# 3. Client joins over localhost
	var join_result: Dictionary = client.join_server("127.0.0.1", PORT)
	_check(join_result.ok, "join_server starts connecting")

	var frames := 0
	while _server_peer_events.is_empty() and frames < 600:
		await process_frame
		frames += 1

	_check(not _server_peer_events.is_empty(), "peer_connected fired on server (waited %d frames)" % frames)
	_check(not _client_connected_events.is_empty(), "connected_to_server fired on client")
	_check(server.multiplayer.get_peers().size() == 1, "server sees exactly 1 connected peer")
	_check(client.multiplayer.get_unique_id() > 1, "client got a non-authority peer id (%d)" % client.multiplayer.get_unique_id())
	_check(server.players.size() == 2, "host player registry has 2 entries")

	# 4. Client leaves -> host registry shrinks
	client.leave()
	frames = 0
	while server.players.size() > 1 and frames < 600:
		await process_frame
		frames += 1
	_check(server.players.size() == 1, "host registry back to 1 after client leave")

	server.leave()
	print("")
	print("Results: %d passed, %d failed, %d total" % [_passed, _failed, _passed + _failed])
	quit(_failed)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)
