extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== test_hand_evaluator ===")
	_run_all()
	print("")
	print("Results: %d passed, %d failed, %d total" % [_passed, _failed, _passed + _failed])
	quit(_failed)


func _run_all() -> void:
	_test_royal_flush()
	_test_straight_flush()
	_test_four_of_a_kind()
	_test_full_house()
	_test_flush()
	_test_straight()
	_test_wheel_straight()
	_test_three_of_a_kind()
	_test_two_pair()
	_test_one_pair()
	_test_high_card()
	_test_seven_card_flush_over_straight()
	_test_seven_card_straight_flush_best()
	_test_pair_kicker()
	_test_two_pair_kicker()
	_test_wheel_beats_high_card_ace()
	_test_compare_equal_pair_split()
	_test_full_house_higher_trips()
	_test_four_kind_kicker()
	_test_high_card_kickers()


func _cards(notations: Array[String]) -> Array[Card]:
	var result: Array[Card] = []
	for n in notations:
		result.append(Card.from_notation(n))
	return result


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(condition: bool, label: String) -> void:
	_assert_eq(condition, true, label)


func _eval(notations: Array[String]) -> Dictionary:
	return HandEvaluator.evaluate_hand(_cards(notations))


func _test_royal_flush() -> void:
	var h := _eval(["Ah", "Kh", "Qh", "Jh", "Th"])
	_assert_eq(h.rank, HandEvaluator.RANK_ROYAL_FLUSH, "royal flush rank")
	_assert_eq(h.rank_name, "Royal Flush", "royal flush name")


func _test_straight_flush() -> void:
	var h := _eval(["9s", "8s", "7s", "6s", "5s"])
	_assert_eq(h.rank, HandEvaluator.RANK_STRAIGHT_FLUSH, "straight flush rank")
	_assert_eq(h.tiebreakers[0], 9, "straight flush high card")


func _test_four_of_a_kind() -> void:
	var h := _eval(["Ac", "Ad", "Ah", "As", "2c"])
	_assert_eq(h.rank, HandEvaluator.RANK_FOUR_KIND, "quads rank")
	_assert_eq(h.tiebreakers[0], 14, "quads rank value")


func _test_full_house() -> void:
	var h := _eval(["Kc", "Kd", "Kh", "3s", "3c"])
	_assert_eq(h.rank, HandEvaluator.RANK_FULL_HOUSE, "full house rank")
	_assert_eq(h.tiebreakers, [13, 3], "full house tiebreakers")


func _test_flush() -> void:
	var h := _eval(["Ac", "Jc", "9c", "5c", "2c"])
	_assert_eq(h.rank, HandEvaluator.RANK_FLUSH, "flush rank")


func _test_straight() -> void:
	var h := _eval(["9h", "8d", "7c", "6s", "5h"])
	_assert_eq(h.rank, HandEvaluator.RANK_STRAIGHT, "straight rank")
	_assert_eq(h.tiebreakers[0], 9, "straight high")


func _test_wheel_straight() -> void:
	var h := _eval(["Ah", "2d", "3c", "4s", "5h"])
	_assert_eq(h.rank, HandEvaluator.RANK_STRAIGHT, "wheel is straight")
	_assert_eq(h.tiebreakers[0], 5, "wheel high is 5 not ace")


func _test_three_of_a_kind() -> void:
	var h := _eval(["Qh", "Qd", "Qc", "7s", "2h"])
	_assert_eq(h.rank, HandEvaluator.RANK_THREE_KIND, "trips rank")
	_assert_eq(h.tiebreakers[0], 12, "trip queens")


func _test_two_pair() -> void:
	var h := _eval(["Jh", "Jd", "4c", "4s", "Ah"])
	_assert_eq(h.rank, HandEvaluator.RANK_TWO_PAIR, "two pair rank")
	_assert_eq(h.tiebreakers, [11, 4, 14], "two pair + ace kicker")


func _test_one_pair() -> void:
	var h := _eval(["Td", "Tc", "9h", "5s", "2c"])
	_assert_eq(h.rank, HandEvaluator.RANK_ONE_PAIR, "one pair rank")
	_assert_eq(h.tiebreakers[0], 10, "pair of tens")


func _test_high_card() -> void:
	var h := _eval(["Ah", "Kd", "9c", "7s", "3h"])
	_assert_eq(h.rank, HandEvaluator.RANK_HIGH_CARD, "high card rank")
	_assert_eq(h.tiebreakers[0], 14, "ace high")


func _test_seven_card_flush_over_straight() -> void:
	# 7 cards contain both a straight and a flush — flush must win.
	var h := _eval(["Ah", "Kh", "Qh", "Jh", "9h", "8d", "7c"])
	_assert_eq(h.rank, HandEvaluator.RANK_FLUSH, "7-card picks flush over straight")


func _test_seven_card_straight_flush_best() -> void:
	var h := _eval(["9h", "8h", "7h", "6h", "5h", "2d", "3c"])
	_assert_eq(h.rank, HandEvaluator.RANK_STRAIGHT_FLUSH, "7-card picks straight flush")


func _test_pair_kicker() -> void:
	var pair_aces_king := _eval(["Ah", "Ad", "Kc", "7s", "2h"])
	var pair_aces_queen := _eval(["Ac", "As", "Qd", "7h", "2c"])
	var cmp := HandEvaluator.compare_hands(pair_aces_king, pair_aces_queen)
	_assert_eq(cmp, 1, "AA+K beats AA+Q")


func _test_two_pair_kicker() -> void:
	var hand_a := _eval(["Kh", "Kd", "9c", "9s", "Ah"])
	var hand_b := _eval(["Kc", "Ks", "9h", "9d", "Qc"])
	var cmp := HandEvaluator.compare_hands(hand_a, hand_b)
	_assert_eq(cmp, 1, "KK99A beats KK99Q")


func _test_wheel_beats_high_card_ace() -> void:
	var wheel := _eval(["Ah", "2d", "3c", "4s", "5h"])
	var ace_high := _eval(["Ad", "Kc", "9h", "7s", "3d"])
	var cmp := HandEvaluator.compare_hands(wheel, ace_high)
	_assert_eq(cmp, 1, "wheel straight beats ace high")


func _test_compare_equal_pair_split() -> void:
	var hand_a := _eval(["8h", "8d", "Kc", "5s", "2h"])
	var hand_b := _eval(["8c", "8s", "Kd", "5h", "2c"])
	var cmp := HandEvaluator.compare_hands(hand_a, hand_b)
	_assert_eq(cmp, 0, "identical pair hands tie")


func _test_full_house_higher_trips() -> void:
	var aaa22 := _eval(["Ah", "Ad", "Ac", "2s", "2h"])
	var kkkqq := _eval(["Kh", "Kd", "Kc", "Qs", "Qh"])
	var cmp := HandEvaluator.compare_hands(aaa22, kkkqq)
	_assert_eq(cmp, 1, "AAA22 beats KKKQQ")


func _test_four_kind_kicker() -> void:
	var quads_aces_king := _eval(["Ah", "Ad", "Ac", "As", "Kh"])
	var quads_aces_queen := _eval(["Ah", "Ad", "Ac", "As", "Qh"])
	var cmp := HandEvaluator.compare_hands(quads_aces_king, quads_aces_queen)
	_assert_eq(cmp, 1, "quads aces + K kicker beats Q")


func _test_high_card_kickers() -> void:
	var a_k_q := _eval(["Ah", "Kd", "Qc", "8s", "3h"])
	var a_k_j := _eval(["Ac", "Ks", "Jd", "8h", "3c"])
	var cmp := HandEvaluator.compare_hands(a_k_q, a_k_j)
	_assert_eq(cmp, 1, "AKQ83 beats AKJ83")
