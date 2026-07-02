class_name GameState
extends RefCounted
## Betting state machine for one table of 2-6 players.
## Tracks per-hand commitments so PotManager can build main/side pots.

enum Phase { PREHAND, PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }

const DEFAULT_STACK := 1000
const SMALL_BLIND := 10
const BIG_BLIND := 20

var num_players: int = 2
var phase: Phase = Phase.PREHAND
var deck: Deck
var button: int = 0
var pot: int = 0
var current_bet: int = 0
var last_raise_size: int = BIG_BLIND
var player_stacks: Dictionary = {}
var player_bets: Dictionary = {} ## chips committed on the current street
var player_committed: Dictionary = {} ## chips committed over the whole hand
var hole_cards: Dictionary = {}
var community_cards: Array[Card] = []
var folded: Dictionary = {}
var all_in: Dictionary = {}
var current_player: int = -1
var hand_over: bool = false
var is_runout_phase: bool = false
var hands_played: int = 0
var last_results: Dictionary = {}
var seats: Array[int] = [] ## players dealt into the current hand
var _acted: Dictionary = {}


func _init(p_num_players: int = 2, p_button: int = 0) -> void:
	num_players = clampi(p_num_players, 2, 6)
	button = p_button % num_players
	for pid in range(num_players):
		player_stacks[pid] = DEFAULT_STACK


func can_start_hand() -> bool:
	var with_chips: int = 0
	for pid in range(num_players):
		if player_stacks[pid] > 0:
			with_chips += 1
	return with_chips >= 2


func start_hand() -> void:
	if not can_start_hand():
		push_error("Cannot start hand: fewer than 2 players with chips")
		return

	seats = []
	for pid in range(num_players):
		if player_stacks[pid] > 0:
			seats.append(pid)
	if hands_played > 0:
		_rotate_button()

	phase = Phase.PREHAND
	hand_over = false
	is_runout_phase = false
	last_results = {}
	pot = 0
	current_bet = 0
	last_raise_size = BIG_BLIND
	current_player = -1
	community_cards.clear()
	player_bets.clear()
	player_committed.clear()
	folded.clear()
	all_in.clear()
	_acted.clear()
	hole_cards.clear()
	for pid in seats:
		player_bets[pid] = 0
		player_committed[pid] = 0
		folded[pid] = false
		all_in[pid] = false
		_acted[pid] = false

	deck = Deck.new()
	deck.shuffle()
	for pid in seats:
		hole_cards[pid] = deck.deal(2)

	_commit_chips(sb_player(), SMALL_BLIND)
	_commit_chips(bb_player(), BIG_BLIND)
	current_bet = BIG_BLIND
	hands_played += 1
	phase = Phase.PREFLOP
	current_player = _next_actor(bb_player())
	if current_player == -1:
		_advance_phase()


func sb_player() -> int:
	## Heads-up: the button posts the small blind.
	return button if seats.size() == 2 else _seat_after(button)


func bb_player() -> int:
	return _seat_after(sb_player())


func get_legal_actions(player_id: int) -> Array[String]:
	if hand_over or is_runout_phase or player_id != current_player:
		return []
	if not player_id in seats or folded[player_id] or all_in[player_id]:
		return []
	if phase == Phase.PREHAND or phase == Phase.SHOWDOWN:
		return []

	var actions: Array[String] = []
	var to_call: int = current_bet - player_bets[player_id]
	var stack: int = player_stacks[player_id]

	if to_call == 0:
		actions.append("check")
	else:
		actions.append("fold")
		if stack > 0:
			actions.append("call") ## partial all-in call allowed when stack < to_call

	var min_raise_total: int = current_bet + maxi(last_raise_size, BIG_BLIND)
	if stack > to_call and stack + player_bets[player_id] >= min_raise_total:
		actions.append("raise")

	if stack > 0:
		actions.append("all_in")

	return actions


func player_action(player_id: int, action: String, amount: int = 0) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": ""}
	if hand_over:
		result.error = "Hand is already over"
		return result
	if player_id != current_player:
		result.error = "Not this player's turn"
		return result
	if action not in get_legal_actions(player_id):
		result.error = "Illegal action: %s" % action
		return result

	match action:
		"fold":
			folded[player_id] = true
			result.ok = true
			if _live_count() == 1:
				_finish_fold_win()
			elif _street_complete():
				_advance_phase()
			else:
				current_player = _next_actor(player_id)
			return result
		"check":
			_acted[player_id] = true
		"call":
			var to_call: int = current_bet - player_bets[player_id]
			_commit_chips(player_id, to_call)
			_acted[player_id] = true
		"raise":
			var min_raise_total: int = current_bet + maxi(last_raise_size, BIG_BLIND)
			if amount < min_raise_total:
				result.error = "Raise must be at least %d" % min_raise_total
				return result
			var needed: int = amount - player_bets[player_id]
			if needed > player_stacks[player_id]:
				result.error = "Not enough chips to raise to %d" % amount
				return result
			last_raise_size = amount - current_bet
			current_bet = amount
			_commit_chips(player_id, needed)
			_mark_raise(player_id)
		"all_in":
			var new_total: int = player_bets[player_id] + player_stacks[player_id]
			if new_total > current_bet:
				last_raise_size = new_total - current_bet
				current_bet = new_total
				_mark_raise(player_id)
			else:
				_acted[player_id] = true
			_commit_chips(player_id, player_stacks[player_id])
		_:
			result.error = "Unknown action"
			return result

	result.ok = true
	if _street_complete():
		_advance_phase()
	else:
		current_player = _next_actor(player_id)
		if current_player == -1:
			_advance_phase()
	return result


## Fold a player out of turn (e.g. network disconnect). Safe no-op otherwise.
func force_fold(pid: int) -> void:
	if hand_over or pid not in seats or folded[pid]:
		return
	folded[pid] = true
	if _live_count() == 1:
		_finish_fold_win()
		return
	if current_player == pid:
		if _street_complete():
			_advance_phase()
		else:
			current_player = _next_actor(pid)
			if current_player == -1:
				_advance_phase()
	elif not is_runout_phase and phase != Phase.SHOWDOWN and _street_complete():
		_advance_phase()


## During a runout (everyone all-in / only one player can act), each call deals
## the next street; at the river it resolves the showdown. UI adds pauses between calls.
func advance_runout() -> void:
	if not is_runout_phase or hand_over:
		return
	if phase == Phase.RIVER:
		_finish_showdown()
	else:
		_deal_next_street()


func showdown_results() -> Dictionary:
	return last_results


func phase_name() -> String:
	return Phase.keys()[phase]


func players_with_chips() -> int:
	var count: int = 0
	for pid in range(num_players):
		if player_stacks[pid] > 0:
			count += 1
	return count


func _rotate_button() -> void:
	var next: int = (button + 1) % num_players
	while next not in seats:
		next = (next + 1) % num_players
	button = next


func _seat_after(pid: int) -> int:
	var idx: int = seats.find(pid)
	return seats[(idx + 1) % seats.size()]


func _can_act(pid: int) -> bool:
	return not folded[pid] and not all_in[pid]


func _next_actor(from_pid: int) -> int:
	var pid: int = _seat_after(from_pid)
	for _i in range(seats.size()):
		if _can_act(pid):
			return pid
		pid = _seat_after(pid)
	return -1


func _actor_count() -> int:
	var count: int = 0
	for pid in seats:
		if _can_act(pid):
			count += 1
	return count


func _live_count() -> int:
	var count: int = 0
	for pid in seats:
		if not folded[pid]:
			count += 1
	return count


func _commit_chips(pid: int, amount: int) -> void:
	var pay: int = mini(amount, player_stacks[pid])
	player_stacks[pid] -= pay
	player_bets[pid] += pay
	player_committed[pid] += pay
	pot += pay
	if player_stacks[pid] == 0:
		all_in[pid] = true


func _mark_raise(pid: int) -> void:
	for other in seats:
		_acted[other] = other == pid


func _street_complete() -> bool:
	for pid in seats:
		if folded[pid] or all_in[pid]:
			continue
		if not _acted[pid] or player_bets[pid] != current_bet:
			return false
	return true


func _advance_phase() -> void:
	current_bet = 0
	last_raise_size = BIG_BLIND
	for pid in seats:
		player_bets[pid] = 0
		_acted[pid] = false

	if phase == Phase.RIVER:
		_finish_showdown()
		return
	if _actor_count() <= 1:
		is_runout_phase = true
		current_player = -1
		return
	_deal_next_street()
	current_player = _next_actor(button)


func _deal_next_street() -> void:
	match phase:
		Phase.PREFLOP:
			community_cards.append_array(deck.deal(3))
			phase = Phase.FLOP
		Phase.FLOP:
			community_cards.append_array(deck.deal(1))
			phase = Phase.TURN
		Phase.TURN:
			community_cards.append_array(deck.deal(1))
			phase = Phase.RIVER
		_:
			pass


func _apply_refunds(refunds: Dictionary) -> void:
	for pid in refunds:
		player_stacks[pid] += refunds[pid]
		pot -= refunds[pid]


func _finish_fold_win() -> void:
	var winner: int = -1
	for pid in seats:
		if not folded[pid]:
			winner = pid
			break

	var built: Dictionary = PotManager.build_pots(player_committed, folded)
	_apply_refunds(built.refunds)
	var total: int = 0
	for pot_entry in built.pots:
		total += pot_entry.amount
		pot_entry["winners"] = [winner]
	player_stacks[winner] += total

	hand_over = true
	is_runout_phase = false
	current_player = -1
	last_results = {
		"reason": "fold",
		"winner": winner,
		"pots": built.pots,
		"refunds": built.refunds,
		"payouts": {winner: total},
		"hands": {},
	}


func _finish_showdown() -> void:
	phase = Phase.SHOWDOWN
	hand_over = true
	is_runout_phase = false
	current_player = -1

	var hands: Dictionary = {}
	for pid in seats:
		if folded[pid]:
			continue
		var seven: Array[Card] = []
		seven.append_array(hole_cards[pid])
		seven.append_array(community_cards)
		hands[pid] = HandEvaluator.evaluate_hand(seven)

	var built: Dictionary = PotManager.build_pots(player_committed, folded)
	_apply_refunds(built.refunds)
	var payouts: Dictionary = PotManager.distribute(built.pots, hands)
	for pid in payouts:
		player_stacks[pid] += payouts[pid]

	last_results = {
		"reason": "showdown",
		"pots": built.pots,
		"refunds": built.refunds,
		"payouts": payouts,
		"hands": hands,
	}
