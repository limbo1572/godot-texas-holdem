extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== test_side_pots ===")
	_test_simple_side_pot()
	_test_double_side_pot_with_refund()
	_test_uneven_call_refund()
	_test_split_pot_two_winners()
	_test_all_in_best_hand_wins_main_only()
	_test_all_in_worst_hand_wins_nothing()
	_test_folded_chips_stay_in_pot()
	_test_gamestate_runout_and_refund()
	print("")
	print("Results: %d passed, %d failed, %d total" % [_passed, _failed, _passed + _failed])
	quit(_failed)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _cards(notations: Array[String]) -> Array[Card]:
	var result: Array[Card] = []
	for n in notations:
		result.append(Card.from_notation(n))
	return result


func _eval(notations: Array[String]) -> Dictionary:
	return HandEvaluator.evaluate_hand(_cards(notations))


## A all-in 50, B and C called 100: main pot 150 (all), side pot 100 (B, C).
func _test_simple_side_pot() -> void:
	var built := PotManager.build_pots(
		{0: 50, 1: 100, 2: 100},
		{0: false, 1: false, 2: false}
	)
	_assert_eq(built.pots.size(), 2, "simple: two pots")
	_assert_eq(built.pots[0].amount, 150, "simple: main pot 150")
	_assert_eq(built.pots[0].eligible, [0, 1, 2], "simple: main pot eligible all")
	_assert_eq(built.pots[1].amount, 100, "simple: side pot 100")
	_assert_eq(built.pots[1].eligible, [1, 2], "simple: side pot excludes short all-in")
	_assert_eq(built.refunds.size(), 0, "simple: no refunds")


## Classic 50/150/300 triple all-in: refund 150, main 150, side 200.
func _test_double_side_pot_with_refund() -> void:
	var built := PotManager.build_pots(
		{0: 50, 1: 150, 2: 300},
		{0: false, 1: false, 2: false}
	)
	_assert_eq(built.refunds.get(2, 0), 150, "double: uncalled 150 refunded to big stack")
	_assert_eq(built.pots.size(), 2, "double: two pots")
	_assert_eq(built.pots[0].amount, 150, "double: main pot 150")
	_assert_eq(built.pots[0].eligible, [0, 1, 2], "double: main eligible all")
	_assert_eq(built.pots[1].amount, 200, "double: side pot 200")
	_assert_eq(built.pots[1].eligible, [1, 2], "double: side eligible two biggest")


## Heads-up all-in 1000 vs call 980: 20 uncalled goes back to the aggressor.
func _test_uneven_call_refund() -> void:
	var built := PotManager.build_pots(
		{0: 1000, 1: 980},
		{0: false, 1: false}
	)
	_assert_eq(built.refunds.get(0, 0), 20, "refund: 20 back to aggressor")
	_assert_eq(built.pots.size(), 1, "refund: single pot")
	_assert_eq(built.pots[0].amount, 1960, "refund: pot is matched chips only")


## Identical hands split the pot evenly.
func _test_split_pot_two_winners() -> void:
	var pots: Array = [{"amount": 200, "eligible": [0, 1]}]
	var hands := {
		0: _eval(["8h", "8d", "Kc", "5s", "2h"]),
		1: _eval(["8c", "8s", "Kd", "5h", "2c"]),
	}
	var payouts := PotManager.distribute(pots, hands)
	_assert_eq(payouts.get(0, 0), 100, "split: player 0 gets half")
	_assert_eq(payouts.get(1, 0), 100, "split: player 1 gets half")
	_assert_eq(pots[0].winners.size(), 2, "split: two winners recorded")


## Short all-in has the best hand: wins main pot only, side pot goes to the
## best of the remaining players even though their hand is worse overall.
func _test_all_in_best_hand_wins_main_only() -> void:
	var pots: Array = [
		{"amount": 150, "eligible": [0, 1, 2]},
		{"amount": 200, "eligible": [1, 2]},
	]
	var hands := {
		0: _eval(["Ah", "Kh", "Qh", "Jh", "Th"]), # royal flush
		1: _eval(["Td", "Tc", "9h", "5s", "2c"]), # pair of tens
		2: _eval(["Ad", "Kc", "9c", "7s", "3d"]), # ace high
	}
	var payouts := PotManager.distribute(pots, hands)
	_assert_eq(payouts.get(0, 0), 150, "per-pot: all-in wins main only")
	_assert_eq(payouts.get(1, 0), 200, "per-pot: side goes to best remaining")
	_assert_eq(payouts.get(2, 0), 0, "per-pot: worst hand gets nothing")


## Short all-in has the worst hand: loses everything, per-pot winners differ from global.
func _test_all_in_worst_hand_wins_nothing() -> void:
	var pots: Array = [
		{"amount": 150, "eligible": [0, 1, 2]},
		{"amount": 200, "eligible": [1, 2]},
	]
	var hands := {
		0: _eval(["7h", "5d", "4c", "3s", "2h"]), # seven high
		1: _eval(["Ah", "Kh", "Qh", "Jh", "Th"]), # royal flush
		2: _eval(["Td", "Tc", "9h", "5s", "2c"]), # pair of tens
	}
	var payouts := PotManager.distribute(pots, hands)
	_assert_eq(payouts.get(1, 0), 350, "worst all-in: best hand takes both pots")
	_assert_eq(payouts.get(0, 0), 0, "worst all-in: short stack gets nothing")


## Folded player's chips stay in the pot but they are not eligible.
func _test_folded_chips_stay_in_pot() -> void:
	var built := PotManager.build_pots(
		{0: 100, 1: 100, 2: 100},
		{0: true, 1: false, 2: false}
	)
	_assert_eq(built.pots.size(), 1, "folded: single pot")
	_assert_eq(built.pots[0].amount, 300, "folded: dead money included")
	_assert_eq(built.pots[0].eligible, [1, 2], "folded: folder not eligible")


## Integration: heads-up 1000 vs 500, all-in + call -> auto-runout, refund, chip conservation.
func _test_gamestate_runout_and_refund() -> void:
	var game := GameState.new(2, 0)
	game.player_stacks = {0: 1000, 1: 500}
	game.start_hand()

	var r1 := game.player_action(0, "all_in")
	_assert_eq(r1.ok, true, "integration: all-in accepted")
	var r2 := game.player_action(1, "call")
	_assert_eq(r2.ok, true, "integration: short call accepted")
	_assert_eq(game.is_runout_phase, true, "integration: runout triggered")

	var safety := 0
	while not game.hand_over and safety < 10:
		game.advance_runout()
		safety += 1
	_assert_eq(game.phase, GameState.Phase.SHOWDOWN, "integration: reached showdown")
	_assert_eq(game.community_cards.size(), 5, "integration: full board dealt")

	var results := game.showdown_results()
	_assert_eq(results.refunds.get(0, 0), 500, "integration: 500 uncalled refunded")

	var total: int = game.player_stacks[0] + game.player_stacks[1]
	_assert_eq(total, 1500, "integration: chips conserved")
