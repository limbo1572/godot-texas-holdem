extends Node
## Autoload "NetGame". Host-authoritative game controller.
## The single GameState lives on the host (or locally in offline mode);
## clients send action requests and render personalized state snapshots.

signal state_updated(snapshot: Dictionary)

const RUNOUT_DELAY := 0.9
const BOT_DELAY := 0.7
const OFFLINE_PLAYERS := 4

var game: GameState
var is_offline: bool = false
var seat_by_peer: Dictionary = {} ## peer_id -> seat (network mode only)
var seat_names: Dictionary = {} ## seat -> display name
var disconnected_seats: Array = []
var status_message: String = ""
var latest_snapshot: Dictionary = {}
var _pumping: bool = false


func _ready() -> void:
	Net.peer_left.connect(_on_peer_left)
	Net.host_left.connect(_on_host_left)


# --- Session start ---

func start_offline(num_players: int = OFFLINE_PLAYERS) -> void:
	is_offline = true
	seat_by_peer = {}
	seat_names = {0: "You"}
	for seat in range(1, num_players):
		seat_names[seat] = "Bot %d" % seat
	disconnected_seats = []
	status_message = ""
	latest_snapshot = {}
	game = GameState.new(num_players)
	game.start_hand()
	get_tree().change_scene_to_file("res://scenes/table.tscn")
	_host_pump()


func host_begin_session() -> void:
	if not multiplayer.is_server():
		return
	var peer_ids: Array = Net.players.keys()
	peer_ids.sort() ## host (1) first, then join order by id
	var mapping: Dictionary = {}
	var names: Dictionary = {}
	for i in range(peer_ids.size()):
		mapping[peer_ids[i]] = i
		names[i] = Net.players[peer_ids[i]]
	begin_session.rpc(mapping, names)


@rpc("authority", "call_local", "reliable")
func begin_session(mapping: Dictionary, names: Dictionary) -> void:
	is_offline = false
	seat_by_peer = mapping
	seat_names = names
	disconnected_seats = []
	status_message = ""
	latest_snapshot = {}
	print("[net] session started, my seat = %s" % str(seat_by_peer.get(multiplayer.get_unique_id(), -1)))
	get_tree().change_scene_to_file("res://scenes/table.tscn")
	if multiplayer.is_server():
		game = GameState.new(mapping.size())
		game.start_hand()
		_host_pump()


# --- Client -> host ---

## UI entry point on every peer (host UI included).
func send_action(action: String, amount: int = 0) -> void:
	if is_offline:
		request_action(action, amount)
	else:
		print("[net] sending action: %s %d" % [action, amount])
		rpc_id(1, "request_action", action, amount)


func request_next_hand() -> void:
	if is_offline:
		rpc_next_hand()
	else:
		rpc_id(1, "rpc_next_hand")


@rpc("any_peer", "call_local", "reliable")
func request_action(action: String, amount: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var seat: int = 0 if (is_offline or sender == 0) else seat_by_peer.get(sender, -1)
	print("[net] request_action from peer %d (seat %d): %s %d" % [sender, seat, action, amount])
	if game == null or seat == -1 or game.hand_over or game.current_player != seat:
		print("[net] rejected: not seat %d's turn" % seat)
		_resync_peer(sender)
		return
	var result: Dictionary = game.player_action(seat, action, amount)
	if not result.ok:
		print("[net] rejected: %s" % result.error)
		_resync_peer(sender)
		return
	_host_pump()


@rpc("any_peer", "call_local", "reliable")
func rpc_next_hand() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 1: ## host-only control
		return
	if game == null or not game.hand_over:
		return
	print("[net] next hand requested")
	for seat in disconnected_seats:
		game.player_stacks[seat] = 0 ## seat out players who left
	if not game.can_start_hand():
		status_message = "Game over — not enough players with chips."
		_broadcast_snapshots()
		return
	status_message = ""
	game.start_hand()
	_host_pump()


# --- Host -> clients ---

@rpc("authority", "call_remote", "reliable")
func sync_state(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	state_updated.emit(snapshot)
	print("[net] snapshot: phase=%s cur_seat=%s pot=%s" % [snapshot.phase, snapshot.current_seat, snapshot.pot])


# --- Host internals ---

## Drives everything that happens without remote input: bot turns (offline)
## and runout pacing. Broadcasts a snapshot after every state change.
func _host_pump() -> void:
	if _pumping:
		return
	_pumping = true
	while true:
		_broadcast_snapshots()
		if game == null or game.hand_over:
			break
		if game.is_runout_phase:
			await get_tree().create_timer(RUNOUT_DELAY).timeout
			game.advance_runout()
			continue
		if is_offline and game.current_player != 0:
			await get_tree().create_timer(BOT_DELAY).timeout
			_bot_act(game.current_player)
			continue
		break ## waiting for a human action (local or remote)
	_pumping = false


func _bot_act(seat: int) -> void:
	var legal: Array[String] = game.get_legal_actions(seat)
	if legal.is_empty():
		return
	var action: String = legal[randi() % legal.size()]
	var amount := 0
	if action == "raise":
		var min_raise: int = game.current_bet + maxi(game.last_raise_size, game.big_blind)
		var max_raise: int = game.player_bets[seat] + game.player_stacks[seat]
		amount = min_raise if max_raise <= min_raise else min_raise + randi() % (max_raise - min_raise + 1)
	game.player_action(seat, action, amount)


func _broadcast_snapshots() -> void:
	if game == null:
		return
	if is_offline:
		var snap := _snapshot_for(0)
		latest_snapshot = snap
		state_updated.emit(snap)
		return
	for peer_id in seat_by_peer:
		var snap := _snapshot_for(seat_by_peer[peer_id])
		if peer_id == multiplayer.get_unique_id():
			latest_snapshot = snap
			state_updated.emit(snap)
		else:
			rpc_id(peer_id, "sync_state", snap)


func _resync_peer(sender: int) -> void:
	if game == null:
		return
	if is_offline or sender <= 1:
		_broadcast_snapshots()
		return
	var seat: int = seat_by_peer.get(sender, -1)
	if seat != -1:
		rpc_id(sender, "sync_state", _snapshot_for(seat))


## Personalized snapshot: viewer sees own hole cards; others' cards are "??"
## until a showdown reveals non-folded hands.
func _snapshot_for(viewer_seat: int) -> Dictionary:
	var results: Dictionary = game.showdown_results() if game.hand_over else {}
	var showdown: bool = game.hand_over and results.get("reason", "") == "showdown"

	var players_arr: Array = []
	for seat in range(game.num_players):
		var seated: bool = seat in game.seats
		var cards: Array = []
		if seated and game.hole_cards.has(seat):
			var reveal: bool = seat == viewer_seat or (showdown and not game.folded[seat])
			for card in game.hole_cards[seat]:
				cards.append(str(card) if reveal else "??")
		players_arr.append({
			"seat": seat,
			"name": seat_names.get(seat, "P%d" % seat),
			"stack": game.player_stacks.get(seat, 0),
			"bet": game.player_bets.get(seat, 0) if seated else 0,
			"folded": seated and game.folded[seat],
			"is_button": seat == game.button,
			"connected": not seat in disconnected_seats,
			"cards": cards,
		})

	var community: Array = []
	for card in game.community_cards:
		community.append(str(card))

	var legal: Array = []
	var to_call := 0
	var min_raise := 0
	var max_raise := 0
	if not game.hand_over and game.current_player == viewer_seat:
		for a in game.get_legal_actions(viewer_seat):
			legal.append(a)
		to_call = mini(game.current_bet - game.player_bets[viewer_seat], game.player_stacks[viewer_seat])
		min_raise = game.current_bet + maxi(game.last_raise_size, game.big_blind)
		max_raise = game.player_bets[viewer_seat] + game.player_stacks[viewer_seat]

	var results_ser: Dictionary = {}
	if not results.is_empty():
		results_ser = {
			"reason": results.reason,
			"payouts": results.payouts,
			"refunds": results.refunds,
			"winner": results.get("winner", -1),
			"pots": [],
			"hands": {},
		}
		for pot_entry in results.pots:
			results_ser.pots.append({
				"amount": pot_entry.amount,
				"eligible": pot_entry.eligible,
				"winners": pot_entry.get("winners", []),
			})
		for seat in results.hands:
			var hand: Dictionary = results.hands[seat]
			var best_five: Array = []
			for card in hand.best_five:
				best_five.append(str(card))
			results_ser.hands[seat] = {"rank_name": hand.rank_name, "best_five": best_five}

	var host_seat: int = 0 if is_offline else seat_by_peer.get(1, 0)
	return {
		"phase": game.phase_name(),
		"pot": game.pot,
		"level": game.current_level,
		"sb": game.small_blind,
		"bb": game.big_blind,
		"level_time_remaining": game.level_time_remaining(),
		"community": community,
		"current_seat": game.current_player if not game.hand_over else -1,
		"your_seat": viewer_seat,
		"players": players_arr,
		"legal_actions": legal,
		"to_call": to_call,
		"min_raise": min_raise,
		"max_raise": max_raise,
		"hand_over": game.hand_over,
		"is_runout": game.is_runout_phase,
		"results": results_ser,
		"can_next_hand": game.hand_over and game.can_start_hand() and viewer_seat == host_seat,
		"game_over": game.hand_over and not game.can_start_hand(),
		"message": status_message,
	}


# --- Disconnects ---

func _on_peer_left(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server() or game == null:
		return
	var seat: int = seat_by_peer.get(peer_id, -1)
	seat_by_peer.erase(peer_id)
	if seat == -1:
		return
	if not seat in disconnected_seats:
		disconnected_seats.append(seat)
	status_message = "%s disconnected — auto-folded." % player_name
	print("[net] %s (seat %d) disconnected, auto-folding" % [player_name, seat])
	if not game.hand_over and seat in game.seats and not game.folded[seat]:
		game.force_fold(seat)
	_host_pump()


func _on_host_left() -> void:
	game = null
	latest_snapshot = {}
	seat_by_peer = {}
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
