class_name GameState
extends RefCounted

enum Phase { PREHAND, PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }

const STARTING_STACK := 1000
const SMALL_BLIND := 10
const BIG_BLIND := 20

var phase: Phase = Phase.PREHAND
var deck: Deck
var button: int = 0
var pot: int = 0
var current_bet: int = 0
var player_stacks: Dictionary = {}
var player_bets: Dictionary = {} ## committed on current betting street
var hole_cards: Dictionary = {}
var community_cards: Array[Card] = []
var folded: Dictionary = {}
var current_player: int = 0
var hand_over: bool = false
var winner_id: int = -1
var last_raise_size: int = BIG_BLIND
var _acted: Dictionary = {}
var _sb_player: int = 0
var _bb_player: int = 1


func _init(p_button: int = 0) -> void:
	button = p_button
	_sb_player = button
	_bb_player = 1 - button
	player_stacks = {0: STARTING_STACK, 1: STARTING_STACK}
	folded = {0: false, 1: false}
	player_bets = {0: 0, 1: 0}
	hole_cards = {0: [], 1: []}


func start_hand() -> void:
	phase = Phase.PREHAND
	hand_over = false
	winner_id = -1
	pot = 0
	current_bet = 0
	player_bets = {0: 0, 1: 0}
	folded = {0: false, 1: false}
	community_cards.clear()
	hole_cards[0] = []
	hole_cards[1] = []

	deck = Deck.new()
	deck.shuffle()
	hole_cards[0] = deck.deal(2)
	hole_cards[1] = deck.deal(2)

	_post_blind(_sb_player, SMALL_BLIND)
	_post_blind(_bb_player, BIG_BLIND)
	current_bet = BIG_BLIND
	last_raise_size = BIG_BLIND
	_reset_street_actions()
	_acted[_sb_player] = false
	_acted[_bb_player] = true ## BB is considered to have matched blind pre-action
	current_player = _sb_player
	phase = Phase.PREFLOP


func get_legal_actions(player_id: int) -> Array[String]:
	if hand_over or folded[player_id] or player_id != current_player:
		return []
	if phase == Phase.PREHAND or phase == Phase.SHOWDOWN:
		return []

	var actions: Array[String] = ["fold"]
	var to_call: int = current_bet - player_bets[player_id]
	var stack: int = player_stacks[player_id]

	if to_call == 0:
		actions.erase("fold")
		actions.append("check")
	else:
		if stack > 0:
			actions.append("call") ## includes partial all-in call when stack < to_call

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
			hand_over = true
			winner_id = 1 - player_id
			result.ok = true
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
				result.error = "Not enough chips to raise"
				return result
			last_raise_size = amount - current_bet
			current_bet = amount
			_commit_chips(player_id, needed)
			_mark_raise(player_id)
		"all_in":
			var all_in_amount: int = player_stacks[player_id]
			var new_total: int = player_bets[player_id] + all_in_amount
			if new_total > current_bet:
				last_raise_size = new_total - current_bet
				current_bet = new_total
				_mark_raise(player_id)
			else:
				_acted[player_id] = true
			_commit_chips(player_id, all_in_amount)
		_:
			result.error = "Unknown action"
			return result

	result.ok = true
	if hand_over:
		return result

	if _street_complete():
		_advance_phase()
	elif action != "fold":
		current_player = 1 - current_player

	return result


func showdown_results() -> Dictionary:
	if winner_id >= 0 and (folded[0] or folded[1]):
		return {
			"winner": winner_id,
			"reason": "fold",
			"hands": {},
		}

	var hands: Dictionary = {}
	for pid in [0, 1]:
		if folded[pid]:
			continue
		var all_cards: Array[Card] = []
		all_cards.append_array(hole_cards[pid])
		all_cards.append_array(community_cards)
		hands[pid] = HandEvaluator.evaluate_hand(all_cards)

	var cmp: int = 0
	if not folded[0] and not folded[1]:
		cmp = HandEvaluator.compare_hands(hands[0], hands[1])
	elif folded[0]:
		cmp = -1
	elif folded[1]:
		cmp = 1

	if cmp > 0:
		winner_id = 0
	elif cmp < 0:
		winner_id = 1
	else:
		winner_id = -1

	return {
		"winner": winner_id,
		"reason": "showdown",
		"hands": hands,
	}


func phase_name() -> String:
	return Phase.keys()[phase]


func _post_blind(player_id: int, amount: int) -> void:
	_commit_chips(player_id, amount)


func _commit_chips(player_id: int, amount: int) -> void:
	var pay: int = mini(amount, player_stacks[player_id])
	player_stacks[player_id] -= pay
	player_bets[player_id] += pay
	pot += pay


func _reset_street_actions() -> void:
	_acted = {0: false, 1: false}


func _mark_raise(player_id: int) -> void:
	_acted[player_id] = true
	_acted[1 - player_id] = false


func _street_complete() -> bool:
	if folded[0] or folded[1]:
		return true
	if player_bets[0] != player_bets[1]:
		return false
	return _acted[0] and _acted[1]


func _advance_phase() -> void:
	player_bets = {0: 0, 1: 0}
	current_bet = 0
	last_raise_size = BIG_BLIND
	_reset_street_actions()

	match phase:
		Phase.PREFLOP:
			community_cards.append_array(deck.deal(3))
			phase = Phase.FLOP
			current_player = _bb_player
		Phase.FLOP:
			community_cards.append(deck.deal(1)[0])
			phase = Phase.TURN
			current_player = _bb_player
		Phase.TURN:
			community_cards.append(deck.deal(1)[0])
			phase = Phase.RIVER
			current_player = _bb_player
		Phase.RIVER:
			phase = Phase.SHOWDOWN
			hand_over = true
			showdown_results()
		_:
			pass


func _cards_to_string(cards: Array[Card]) -> String:
	var parts: PackedStringArray = []
	for card in cards:
		parts.append(str(card))
	return " ".join(parts)
