extends Control
## Local (hot-seat vs bots) poker table UI. Player 0 is human, others are random bots.

const NUM_PLAYERS := 4
const HUMAN_ID := 0
const BOT_DELAY := 0.7
const RUNOUT_DELAY := 0.9
const CARD_SIZE := Vector2(52, 74)

const SUIT_SYMBOLS: Dictionary = {
	Card.Suit.HEARTS: "\u2665",
	Card.Suit.DIAMONDS: "\u2666",
	Card.Suit.CLUBS: "\u2663",
	Card.Suit.SPADES: "\u2660",
}

var game: GameState

var _seat_panels: Dictionary = {}
var _seat_name_labels: Dictionary = {}
var _seat_stack_labels: Dictionary = {}
var _seat_bet_labels: Dictionary = {}
var _seat_card_boxes: Dictionary = {}

var _community_box: HBoxContainer
var _pot_label: Label
var _phase_label: Label
var _status_label: Label

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
	game = GameState.new(NUM_PLAYERS)
	_build_ui()
	resized.connect(_layout_seats)
	call_deferred("_layout_seats")
	_start_hand()


func _start_hand() -> void:
	if not game.can_start_hand():
		_status_label.text = "Game over — not enough players with chips."
		_next_hand_btn.visible = false
		return
	game.start_hand()
	_next_hand_btn.visible = false
	_status_label.text = ""
	_refresh()
	_drive()


func _drive() -> void:
	while true:
		if game.hand_over:
			_show_showdown()
			return
		if game.is_runout_phase:
			await get_tree().create_timer(RUNOUT_DELAY).timeout
			game.advance_runout()
			_refresh()
			continue
		if game.current_player == HUMAN_ID:
			_show_actions()
			return
		await get_tree().create_timer(BOT_DELAY).timeout
		_bot_act(game.current_player)
		_refresh()


func _bot_act(pid: int) -> void:
	var legal: Array[String] = game.get_legal_actions(pid)
	if legal.is_empty():
		return
	var action: String = legal[randi() % legal.size()]
	var amount := 0
	if action == "raise":
		var min_raise: int = game.current_bet + maxi(game.last_raise_size, GameState.BIG_BLIND)
		var max_raise: int = game.player_bets[pid] + game.player_stacks[pid]
		amount = min_raise if max_raise <= min_raise else min_raise + randi() % (max_raise - min_raise + 1)
	game.player_action(pid, action, amount)


# --- Human actions ---

func _show_actions() -> void:
	var legal: Array[String] = game.get_legal_actions(HUMAN_ID)
	_action_bar.visible = true
	_fold_btn.visible = "fold" in legal
	_check_btn.visible = "check" in legal
	_call_btn.visible = "call" in legal
	if "call" in legal:
		var to_call: int = mini(game.current_bet - game.player_bets[HUMAN_ID], game.player_stacks[HUMAN_ID])
		_call_btn.text = "Call %d" % to_call
	var can_raise := "raise" in legal
	_raise_btn.visible = can_raise
	_raise_slider.visible = can_raise
	_raise_amount_label.visible = can_raise
	if can_raise:
		_raise_slider.min_value = game.current_bet + maxi(game.last_raise_size, GameState.BIG_BLIND)
		_raise_slider.max_value = game.player_bets[HUMAN_ID] + game.player_stacks[HUMAN_ID]
		_raise_slider.value = _raise_slider.min_value
		_raise_amount_label.text = str(int(_raise_slider.value))
	_allin_btn.visible = "all_in" in legal


func _human_act(action: String, amount: int = 0) -> void:
	_action_bar.visible = false
	var result: Dictionary = game.player_action(HUMAN_ID, action, amount)
	if not result.ok:
		_status_label.text = result.error
		_show_actions()
		return
	_refresh()
	_drive()


func _on_fold() -> void:
	_human_act("fold")


func _on_check() -> void:
	_human_act("check")


func _on_call() -> void:
	_human_act("call")


func _on_raise() -> void:
	_human_act("raise", int(_raise_slider.value))


func _on_all_in() -> void:
	_human_act("all_in")


func _on_next_hand() -> void:
	_start_hand()


func _on_slider_changed(value: float) -> void:
	_raise_amount_label.text = str(int(value))


# --- Showdown ---

func _show_showdown() -> void:
	_action_bar.visible = false
	_refresh()
	var results: Dictionary = game.showdown_results()
	var lines: PackedStringArray = []
	if results.reason == "fold":
		lines.append("%s wins %d — everyone folded." % [_player_name(results.winner), results.payouts[results.winner]])
	else:
		var pot_index := 0
		for pot_entry in results.pots:
			pot_index += 1
			var kind := "Main pot" if pot_index == 1 else "Side pot %d" % (pot_index - 1)
			var winner_names: PackedStringArray = []
			for pid in pot_entry.winners:
				winner_names.append(_player_name(pid))
			lines.append("%s (%d): %s" % [kind, pot_entry.amount, ", ".join(winner_names)])
		for pid in results.payouts:
			lines.append("%s collects %d" % [_player_name(pid), results.payouts[pid]])
	for pid in results.refunds:
		lines.append("%s refunded %d (uncalled)" % [_player_name(pid), results.refunds[pid]])
	_status_label.text = "\n".join(lines)
	_next_hand_btn.visible = game.can_start_hand()
	if not game.can_start_hand():
		_status_label.text += "\nGame over."


# --- UI construction ---

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var table := Panel.new()
	table.name = "TableFelt"
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

	for pid in range(NUM_PLAYERS):
		_build_seat(pid)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status_label.offset_left = 12.0
	_status_label.offset_bottom = -8.0
	add_child(_status_label)

	_build_action_bar()


func _build_seat(pid: int) -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	_seat_panels[pid] = panel

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	_seat_name_labels[pid] = name_label

	var cards_box := HBoxContainer.new()
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards_box)
	_seat_card_boxes[pid] = cards_box

	var stack_label := Label.new()
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stack_label)
	_seat_stack_labels[pid] = stack_label

	var bet_label := Label.new()
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bet_label)
	_seat_bet_labels[pid] = bet_label


func _build_action_bar() -> void:
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.offset_bottom = -10.0
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.visible = false
	add_child(_action_bar)

	_fold_btn = _make_button("Fold", _on_fold)
	_check_btn = _make_button("Check", _on_check)
	_call_btn = _make_button("Call", _on_call)

	_raise_slider = HSlider.new()
	_raise_slider.custom_minimum_size = Vector2(160, 24)
	_raise_slider.step = 10
	_raise_slider.value_changed.connect(_on_slider_changed)
	_action_bar.add_child(_raise_slider)

	_raise_amount_label = Label.new()
	_action_bar.add_child(_raise_amount_label)

	_raise_btn = _make_button("Raise", _on_raise)
	_allin_btn = _make_button("All-In", _on_all_in)

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
	if view.x < 10.0 or view.y < 10.0:
		return
	var center := view / 2.0
	var radius := Vector2(view.x * 0.38, view.y * 0.36)
	for pid in range(NUM_PLAYERS):
		var panel: PanelContainer = _seat_panels[pid]
		var angle := PI / 2.0 + TAU * float(pid) / float(NUM_PLAYERS)
		var pos := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		panel.position = pos - panel.size / 2.0


# --- Refresh ---

func _refresh() -> void:
	_phase_label.text = game.phase_name()
	_pot_label.text = "Pot: %d" % game.pot

	_clear_children(_community_box)
	for card in game.community_cards:
		_community_box.add_child(_make_card_node(card, true))

	var showdown_reveal: bool = game.hand_over \
		and game.last_results.get("reason", "") == "showdown"

	for pid in range(NUM_PLAYERS):
		var seated: bool = pid in game.seats
		var is_folded: bool = seated and game.folded[pid]

		var tag := ""
		if seated and pid == game.button:
			tag += " (D)"
		if is_folded:
			tag += " [fold]"
		_seat_name_labels[pid].text = _player_name(pid) + tag
		_seat_stack_labels[pid].text = "Stack: %d" % game.player_stacks[pid]
		_seat_bet_labels[pid].text = "Bet: %d" % (game.player_bets.get(pid, 0) if seated else 0)

		var cards_box: HBoxContainer = _seat_card_boxes[pid]
		_clear_children(cards_box)
		if seated and game.hole_cards.has(pid):
			var face_up: bool = pid == HUMAN_ID or (showdown_reveal and not is_folded)
			for card in game.hole_cards[pid]:
				cards_box.add_child(_make_card_node(card, face_up))

		var panel: PanelContainer = _seat_panels[pid]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.16, 0.2)
		style.set_corner_radius_all(8)
		style.set_border_width_all(3)
		if seated and pid == game.current_player and not game.hand_over:
			style.border_color = Color(1.0, 0.85, 0.2)
		else:
			style.border_color = Color(0.3, 0.3, 0.35)
		panel.add_theme_stylebox_override("panel", style)
		panel.modulate = Color(1, 1, 1, 0.45) if (is_folded or not seated) else Color.WHITE

	call_deferred("_layout_seats")


func _make_card_node(card: Card, face_up: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0.2, 0.2, 0.2)
	if face_up:
		style.bg_color = Color.WHITE
		var label := Label.new()
		label.text = "%s%s" % [card.rank_char(), SUIT_SYMBOLS[card.suit]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var is_red: bool = card.suit == Card.Suit.HEARTS or card.suit == Card.Suit.DIAMONDS
		label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1) if is_red else Color.BLACK)
		label.add_theme_font_size_override("font_size", 20)
		panel.add_child(label)
	else:
		style.bg_color = Color(0.15, 0.2, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _player_name(pid: int) -> String:
	return "You" if pid == HUMAN_ID else "Bot %d" % pid


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
