extends Control
## Lobby: host / join a LAN game, or play offline vs bots.

const DEFAULT_PORT := 8910

var _port_edit: LineEdit
var _addr_edit: LineEdit
var _host_btn: Button
var _join_btn: Button
var _offline_btn: Button
var _start_btn: Button
var _status: Label
var _players_box: VBoxContainer
var _waiting: Label


func _ready() -> void:
	_build_ui()
	Net.players_changed.connect(_refresh_players)
	Net.connected_as_client.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)
	if Net.last_error != "":
		_status.text = Net.last_error
		Net.last_error = ""
	_refresh_players()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "LocalPoker — LAN Texas Hold'em"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	box.add_child(host_row)
	var port_label := Label.new()
	port_label.text = "Port:"
	host_row.add_child(port_label)
	_port_edit = LineEdit.new()
	_port_edit.text = str(DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(100, 0)
	host_row.add_child(_port_edit)
	_host_btn = Button.new()
	_host_btn.text = "Host Game"
	_host_btn.pressed.connect(_on_host_pressed)
	host_row.add_child(_host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	var addr_label := Label.new()
	addr_label.text = "Address:"
	join_row.add_child(addr_label)
	_addr_edit = LineEdit.new()
	_addr_edit.text = "127.0.0.1:%d" % DEFAULT_PORT
	_addr_edit.custom_minimum_size = Vector2(200, 0)
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_addr_edit)
	_join_btn = Button.new()
	_join_btn.text = "Join Game"
	_join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_btn)

	_offline_btn = Button.new()
	_offline_btn.text = "Play Offline vs Bots"
	_offline_btn.pressed.connect(func() -> void: NetGame.start_offline())
	box.add_child(_offline_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	box.add_child(_status)

	var players_title := Label.new()
	players_title.text = "Players:"
	box.add_child(players_title)

	_players_box = VBoxContainer.new()
	box.add_child(_players_box)

	_start_btn = Button.new()
	_start_btn.text = "Start Game"
	_start_btn.visible = false
	_start_btn.pressed.connect(func() -> void: NetGame.host_begin_session())
	box.add_child(_start_btn)

	_waiting = Label.new()
	_waiting.text = "Waiting for host to start..."
	_waiting.visible = false
	box.add_child(_waiting)


func _on_host_pressed() -> void:
	var port: int = _port_edit.text.to_int()
	if port < 1024 or port > 65535:
		_status.text = "Invalid port (use 1024-65535)."
		return
	var result: Dictionary = Net.create_server(port)
	if not result.ok:
		_status.text = result.error
		return
	_status.text = "Hosting on port %d. Waiting for players..." % port
	_set_inputs_enabled(false)


func _on_join_pressed() -> void:
	var text: String = _addr_edit.text.strip_edges()
	if text.is_empty():
		_status.text = "Enter host address (ip:port)."
		return
	var ip: String = text
	var port: int = DEFAULT_PORT
	if ":" in text:
		var parts: PackedStringArray = text.rsplit(":", true, 1)
		ip = parts[0]
		port = parts[1].to_int()
	if ip.is_empty() or port < 1 or port > 65535:
		_status.text = "Invalid address. Use format 192.168.1.10:8910"
		return
	var result: Dictionary = Net.join_server(ip, port)
	if not result.ok:
		_status.text = result.error
		return
	_status.text = "Connecting to %s:%d ..." % [ip, port]
	_set_inputs_enabled(false)


func _on_joined() -> void:
	_status.text = "Connected! Waiting for host to start the game..."
	_waiting.visible = true


func _on_join_failed(reason: String) -> void:
	_status.text = reason
	_set_inputs_enabled(true)
	_waiting.visible = false


func _refresh_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var label := Label.new()
		var me: String = "  (you)" if id == multiplayer.get_unique_id() and Net.active else ""
		label.text = "- %s [id %d]%s" % [Net.players[id], id, me]
		_players_box.add_child(label)
	_start_btn.visible = Net.is_host
	_start_btn.disabled = Net.players.size() < 2
	if Net.is_host and Net.players.size() >= 2:
		_status.text = "%d players connected. Ready to start!" % Net.players.size()


func _set_inputs_enabled(enabled: bool) -> void:
	_host_btn.disabled = not enabled
	_join_btn.disabled = not enabled
	_offline_btn.disabled = not enabled
	_port_edit.editable = enabled
	_addr_edit.editable = enabled
