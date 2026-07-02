extends SceneTree
## Headless debug harness: one full hand with random legal bot actions.

const NUM_PLAYERS := 4
const MAX_STEPS := 300


func _init() -> void:
	print("=== LocalPoker — %d-player test hand ===" % NUM_PLAYERS)
	var game := GameState.new(NUM_PLAYERS, randi() % NUM_PLAYERS)
	game.start_hand()
	print("Button: P%d | SB: P%d (%d) | BB: P%d (%d)" % [
		game.button, game.sb_player(), GameState.SMALL_BLIND, game.bb_player(), GameState.BIG_BLIND,
	])
	for pid in game.seats:
		print("P%d hole: %s | stack: %d" % [pid, _cards_line(game.hole_cards[pid]), game.player_stacks[pid]])

	var prev_phase: int = game.phase
	var steps := 0
	while not game.hand_over and steps < MAX_STEPS:
		steps += 1
		if game.is_runout_phase:
			game.advance_runout()
			print("[runout] %s | community: %s" % [game.phase_name(), _cards_line(game.community_cards)])
			continue

		if game.phase != prev_phase:
			prev_phase = game.phase
			print("")
			print("--- %s --- community: %s" % [game.phase_name(), _cards_line(game.community_cards)])

		var pid: int = game.current_player
		var legal: Array[String] = game.get_legal_actions(pid)
		if legal.is_empty():
			push_error("No legal actions for P%d in %s" % [pid, game.phase_name()])
			break
		var action: String = legal[randi() % legal.size()]
		var amount := 0
		if action == "raise":
			amount = _random_raise_amount(game, pid)
		var result: Dictionary = game.player_action(pid, action, amount)
		if not result.ok:
			push_error("Action failed: %s" % result.error)
			break
		print("P%d -> %s%s | pot=%d" % [pid, action, (" to %d" % amount) if action == "raise" else "", game.pot])

	_print_results(game)
	quit()


func _random_raise_amount(game: GameState, pid: int) -> int:
	var min_raise: int = game.current_bet + maxi(game.last_raise_size, GameState.BIG_BLIND)
	var max_raise: int = game.player_bets[pid] + game.player_stacks[pid]
	if max_raise <= min_raise:
		return min_raise
	return min_raise + randi() % (max_raise - min_raise + 1)


func _print_results(game: GameState) -> void:
	print("")
	print("=== RESULT ===")
	var results: Dictionary = game.showdown_results()
	if results.is_empty():
		print("No results (hand did not finish)")
		return

	if results.reason == "fold":
		print("P%d wins %d (everyone else folded)" % [results.winner, results.payouts[results.winner]])
	else:
		print("Community: %s" % _cards_line(game.community_cards))
		for pid in results.hands:
			var hand: Dictionary = results.hands[pid]
			print("P%d: %s | best five: %s" % [pid, hand.rank_name, _cards_line(hand.best_five)])
		var pot_index := 0
		for pot_entry in results.pots:
			pot_index += 1
			var kind := "main" if pot_index == 1 else "side %d" % (pot_index - 1)
			print("Pot (%s): %d | eligible: %s | winners: %s" % [
				kind, pot_entry.amount, str(pot_entry.eligible), str(pot_entry.winners),
			])
		for pid in results.payouts:
			print("P%d collects %d" % [pid, results.payouts[pid]])

	for pid in results.refunds:
		print("P%d refunded %d (uncalled)" % [pid, results.refunds[pid]])
	print("Final stacks: %s" % str(game.player_stacks))


func _cards_line(cards: Array[Card]) -> String:
	if cards.is_empty():
		return "(none)"
	var parts: PackedStringArray = []
	for card in cards:
		parts.append(str(card))
	return " ".join(parts)
