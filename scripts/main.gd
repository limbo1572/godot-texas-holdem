extends SceneTree

const MAX_ACTIONS := 80


func _init() -> void:
	print("=== LocalPoker — heads-up test hand ===")
	var game := GameState.new(randi() % 2)
	game.start_hand()
	print("Button: player %d | SB=%d BB=%d" % [game.button, GameState.SMALL_BLIND, GameState.BIG_BLIND])
	print("Stacks: P0=%d P1=%d" % [game.player_stacks[0], game.player_stacks[1]])
	_print_phase(game)

	var safety := 0
	while not game.hand_over and safety < MAX_ACTIONS:
		var pid: int = game.current_player
		var legal: Array[String] = game.get_legal_actions(pid)
		if legal.is_empty():
			push_error("No legal actions for player %d in phase %s" % [pid, game.phase_name()])
			break
		var action: String = legal[randi() % legal.size()]
		var amount: int = 0
		if action == "raise":
			amount = _random_raise_amount(game, pid)
		var result: Dictionary = game.player_action(pid, action, amount)
		if not result.ok:
			push_error("Action failed: %s" % result.error)
			break
		print("P%d -> %s%s | pot=%d stacks=[%d,%d] bets=[%d,%d]" % [
			pid,
			action,
			(" to %d" % amount) if action == "raise" else "",
			game.pot,
			game.player_stacks[0],
			game.player_stacks[1],
			game.player_bets[0],
			game.player_bets[1],
		])
		if game.phase == GameState.Phase.SHOWDOWN or (game.hand_over and game.phase != GameState.Phase.RIVER):
			_print_phase(game)
		elif _street_just_completed(game):
			_print_phase(game)
		safety += 1

	_finish_hand(game)
	quit()


func _street_just_completed(game: GameState) -> bool:
	return game.player_bets[0] == 0 and game.player_bets[1] == 0 and game.current_bet == 0 \
		and game.phase != GameState.Phase.PREFLOP and not game.hand_over


func _random_raise_amount(game: GameState, player_id: int) -> int:
	var min_raise: int = game.current_bet + maxi(game.last_raise_size, GameState.BIG_BLIND)
	var max_raise: int = game.player_bets[player_id] + game.player_stacks[player_id]
	if max_raise <= min_raise:
		return min_raise
	return min_raise + randi() % (max_raise - min_raise + 1)


func _print_phase(game: GameState) -> void:
	print("")
	print("--- %s ---" % game.phase_name())
	print("Community: %s" % _cards_line(game.community_cards))
	print("P0 hole: %s" % _cards_line(game.hole_cards[0]))
	print("P1 hole: %s" % _cards_line(game.hole_cards[1]))


func _finish_hand(game: GameState) -> void:
	print("")
	print("=== SHOWDOWN ===")
	var outcome: Dictionary = game.showdown_results()
	if outcome.reason == "fold":
		print("Winner: Player %d (opponent folded)" % outcome.winner)
		return

	var hands: Dictionary = outcome.hands
	for pid in [0, 1]:
		var hand: Dictionary = hands[pid]
		print("P%d: %s | best five: %s | kickers: %s" % [
			pid,
			hand.rank_name,
			_cards_line(hand.best_five),
			str(hand.tiebreakers),
		])
	if outcome.winner == -1:
		print("Result: SPLIT POT")
	else:
		print("Winner: Player %d" % outcome.winner)
	print("Final pot: %d" % game.pot)


func _cards_line(cards: Array[Card]) -> String:
	if cards.is_empty():
		return "(none)"
	var parts: PackedStringArray = []
	for card in cards:
		parts.append(str(card))
	return " ".join(parts)
