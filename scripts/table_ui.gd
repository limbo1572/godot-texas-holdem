extends Control
## Poker table UI. Renders personalized snapshots from NetGame and sends
## action requests back — never touches GameState directly.

const CARD_SIZE := Vector2(52, 74)
const SUIT_SYMBOLS: Dictionary = {
	"h": "\u2665",
	"d": "\u2666",
	"c": "\u2663",
	"s": "\u2660",
}

var _snapshot: Dictionary = {}
var _built_seats: int = -1

var _seat_panels: Array = []
var _seat_name_labels: Array = []
var _seat_stack_labels: Array = []
var _seat_bet_labels: Array = []
var _seat_card_boxes: Array = []

var _community_box: HBoxContainer
var _pot_label: Label
var _phase_label: Label
var _status_label: Label
var _level_label: Label
var _toast_label: Label

## Countdown display: authoritative value comes from host snapshots; between
## snapshots we only tick the displayed value down locally (presentation only).
var _level_remaining: float = -1.0
var _last_level_seen: int = -1
var _level_line: String = ""
var _toast_serial: int = 0

var _action_bar: HBoxContainer
var _fold_btn: Button
var _check_btn: Button
var _call_btn: Button
var _raise_btn: Button
var _allin_btn: Button
var _raise_slider: HSlider
var _raise_amount_label: Label
var _next_hand_btn: Button


func _ready() -> void:
	_build_ui()
	resized.connect(_layout_seats)
	NetGame.state_updated.connect(_on_state)
	if not NetGame.latest_snapshot.is_empty():
		_on_state(NetGame.latest_snapshot)


func _on_state(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_ensure_seats(snapshot.players.size())
	_update_blind_info(snapshot)
	_refresh()


func _process(delta: float) -> void:
	if _level_remaining > 0.0:
		_level_remaining = maxf(0.0, _level_remaining - delta)
		_render_level_label()


func _update_blind_info(snap: Dictionary) -> void:
	var level: int = snap.get("level", 0)
	_level_line = "Level %d — blinds %d/%d" % [level + 1, snap.get("sb", 0), snap.get("bb", 0)]
	_level_remaining = snap.get("level_time_remaining", -1.0)
	_render_level_label()
	if _last_level_seen != -1 and level > _last_level_seen:
		_show_toast("Blinds increased: %d/%d" % [snap.sb, snap.bb])
	_last_level_seen = level


func _render_level_label() -> void:
	if _level_remaining >= 0.0:
		var secs := int(ceil(_level_remaining))
		_level_label.text = "%s\nNext level in %02d:%02d" % [_level_line, secs / 60, secs % 60]
	else:
		_level_label.text = "%s\nFinal level" % _level_line


func _show_toast(text: String) -> void:
	_toast_serial += 1
	var serial := _toast_serial
	_toast_label.text = text
	_toast_label.visible = true
	await get_tree().create_timer(3.0).timeout
	if serial == _toast_serial:
		_toast_label.visible = false


# --- Actions ---

func _send(action: String, amount: int = 0) -> void:
	_action_bar.visible = false
	NetGame.send_action(action, amount)


func _on_next_hand() -> void:
	_next_hand_btn.visible = false
	NetGame.request_next_hand()


func _on_slider_changed(value: float) -> void:
	_raise_amount_label.text = str(int(value))


# --- Rendering ---

func _refresh() -> void:
	var snap := _snapshot
	_phase_label.text = snap.phase
	_pot_label.text = "Pot: %d" % snap.pot

	_clear_children(_community_box)
	for notation in snap.community:
		_community_box.add_child(_make_card_node(notation))

	var n: int = snap.players.size()
	for entry in snap.players:
		var idx: int = (int(entry.seat) - int(snap.your_seat) + n) % n
		var tag := ""
		if entry.seat == snap.your_seat:
			tag += " (you)"
		if entry.is_button:
			tag += " (D)"
		if entry.folded:
			tag += " [fold]"
		if not entry.connected:
			tag += " [offline]"
		_seat_name_labels[idx].text = entry.name + tag
		_seat_stack_labels[idx].text = "Stack: %d" % entry.stack
		_seat_bet_labels[idx].text = "Bet: %d" % entry.bet

		var cards_box: HBoxContainer = _seat_card_boxes[idx]
		_clear_children(cards_box)
		for notation in entry.cards:
			cards_box.add_child(_make_card_node(notation))

		var panel: PanelContainer = _seat_panels[idx]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.16, 0.2)
		style.set_corner_radius_all(8)
		style.set_border_width_all(3)
		if entry.seat == snap.current_seat:
			style.border_color = Color(1.0, 0.85, 0.2)
		else:
			style.border_color = Color(0.3, 0.3, 0.35)
		panel.add_theme_stylebox_override("panel", style)
		var dimmed: bool = entry.folded or not entry.connected
		panel.modulate = Color(1, 1, 1, 0.45) if dimmed else Color.WHITE

	_refresh_action_bar(snap)
	_refresh_status(snap)
	call_deferred("_layout_seats")


func _refresh_action_bar(snap: Dictionary) -> void:
	var legal: Array = snap.legal_actions
	_action_bar.visible = not legal.is_empty()
	if legal.is_empty():
		return
	_fold_btn.visible = "fold" in legal
	_check_btn.visible = "check" in legal
	_call_btn.visible = "call" in legal
	if "call" in legal:
		_call_btn.text = "Call %d" % snap.to_call
	var can_raise: bool = "raise" in legal
	_raise_btn.visible = can_raise
	_raise_slider.visible = can_raise
	_raise_amount_label.visible = can_raise
	if can_raise:
		_raise_slider.min_value = snap.min_raise
		_raise_slider.max_value = snap.max_raise
		_raise_slider.value = snap.min_raise
		_raise_amount_label.text = str(snap.min_raise)
	_allin_btn.visible = "all_in" in legal


func _refresh_status(snap: Dictionary) -> void:
	var lines: PackedStringArray = []
	if snap.message != "":
		lines.append(snap.message)

	if snap.hand_over and not snap.results.is_empty():
		var names: Dictionary = {}
		for entry in snap.players:
			names[int(entry.seat)] = entry.name
		var results: Dictionary = snap.results
		if results.reason == "fold":
			lines.append("%s wins %d — everyone folded." % [
				names.get(int(results.winner), "?"), results.payouts.values()[0],
			])
		else:
			var pot_index := 0
			for pot_entry in results.pots:
				pot_index += 1
				var kind: String = "Main pot" if pot_index == 1 else "Side pot %d" % (pot_index - 1)
				var winner_names: PackedStringArray = []
				for seat in pot_entry.winners:
					winner_names.append(names.get(int(seat), "?"))
				lines.append("%s (%d): %s" % [kind, pot_entry.amount, ", ".join(winner_names)])
			for seat in results.payouts:
				lines.append("%s collects %d" % [names.get(int(seat), "?"), results.payouts[seat]])
		for seat in results.refunds:
			lines.append("%s refunded %d (uncalled)" % [names.get(int(seat), "?"), results.refunds[seat]])

	if snap.game_over:
		lines.append("Game over.")
	elif snap.hand_over and not snap.can_next_hand:
		lines.append("Waiting for host to start the next hand...")

	_status_label.text = "\n".join(lines)
	_next_hand_btn.visible = snap.can_next_hand


# --- UI construction ---

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var table := Panel.new()
	table.set_anchors_preset(Control.PRESET_FULL_RECT)
	table.offset_left = 140.0
	table.offset_right = -140.0
	table.offset_top = 70.0
	table.offset_bottom = -150.0
	var felt := StyleBoxFlat.new()
	felt.bg_color = Color(0.1, 0.35, 0.18)
	felt.set_corner_radius_all(220)
	felt.border_color = Color(0.35, 0.22, 0.1)
	felt.set_border_width_all(10)
	table.add_theme_stylebox_override("panel", felt)
	add_child(table)

	var center_box := VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center_box)

	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_phase_label)

	_community_box = HBoxContainer.new()
	_community_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_child(_community_box)

	_pot_label = Label.new()
	_pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_pot_label)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status_label.offset_left = 12.0
	_status_label.offset_bottom = -8.0
	add_child(_status_label)

	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_level_label.offset_left = 12.0
	_level_label.offset_top = 8.0
	add_child(_level_label)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.offset_top = 12.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_toast_label.visible = false
	add_child(_toast_label)

	_build_action_bar()


func _ensure_seats(count: int) -> void:
	if _built_seats == count:
		return
	_built_seats = count
	for panel in _seat_panels:
		panel.queue_free()
	_seat_panels.clear()
	_seat_name_labels.clear()
	_seat_stack_labels.clear()
	_seat_bet_labels.clear()
	_seat_card_boxes.clear()
	for _i in range(count):
		_build_seat()
	_layout_seats()


func _build_seat() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	_seat_panels.append(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	_seat_name_labels.append(name_label)

	var cards_box := HBoxContainer.new()
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards_box)
	_seat_card_boxes.append(cards_box)

	var stack_label := Label.new()
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stack_label)
	_seat_stack_labels.append(stack_label)

	var bet_label := Label.new()
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bet_label)
	_seat_bet_labels.append(bet_label)


func _build_action_bar() -> void:
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.offset_bottom = -10.0
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.visible = false
	add_child(_action_bar)

	_fold_btn = _make_button("Fold", func() -> void: _send("fold"))
	_check_btn = _make_button("Check", func() -> void: _send("check"))
	_call_btn = _make_button("Call", func() -> void: _send("call"))

	_raise_slider = HSlider.new()
	_raise_slider.custom_minimum_size = Vector2(160, 24)
	_raise_slider.step = 10
	_raise_slider.value_changed.connect(_on_slider_changed)
	_action_bar.add_child(_raise_slider)

	_raise_amount_label = Label.new()
	_action_bar.add_child(_raise_amount_label)

	_raise_btn = _make_button("Raise", func() -> void: _send("raise", int(_raise_slider.value)))
	_allin_btn = _make_button("All-In", func() -> void: _send("all_in"))

	_next_hand_btn = Button.new()
	_next_hand_btn.text = "Next Hand"
	_next_hand_btn.visible = false
	_next_hand_btn.pressed.connect(_on_next_hand)
	_next_hand_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_next_hand_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_next_hand_btn.offset_right = -16.0
	add_child(_next_hand_btn)


func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	_action_bar.add_child(btn)
	return btn


func _layout_seats() -> void:
	var view := size
	if view.x < 10.0 or view.y < 10.0 or _seat_panels.is_empty():
		return
	var center := view / 2.0
	var radius := Vector2(view.x * 0.38, view.y * 0.36)
	var n := _seat_panels.size()
	for i in range(n):
		var panel: PanelContainer = _seat_panels[i]
		var angle := PI / 2.0 + TAU * float(i) / float(n)
		var pos := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		panel.position = pos - panel.size / 2.0


func _make_card_node(notation: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0.2, 0.2, 0.2)
	if notation == "??":
		style.bg_color = Color(0.15, 0.2, 0.5)
	else:
		style.bg_color = Color.WHITE
		var suit_char: String = notation.substr(notation.length() - 1, 1)
		var rank_part: String = notation.substr(0, notation.length() - 1)
		var label := Label.new()
		label.text = "%s%s" % [rank_part, SUIT_SYMBOLS.get(suit_char, "?")]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var is_red: bool = suit_char == "h" or suit_char == "d"
		label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1) if is_red else Color.BLACK)
		label.add_theme_font_size_override("font_size", 20)
		panel.add_child(label)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
