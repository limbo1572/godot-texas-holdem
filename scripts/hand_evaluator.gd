class_name HandEvaluator
extends RefCounted

const RANK_HIGH_CARD := 0
const RANK_ONE_PAIR := 1
const RANK_TWO_PAIR := 2
const RANK_THREE_KIND := 3
const RANK_STRAIGHT := 4
const RANK_FLUSH := 5
const RANK_FULL_HOUSE := 6
const RANK_FOUR_KIND := 7
const RANK_STRAIGHT_FLUSH := 8
const RANK_ROYAL_FLUSH := 9

const RANK_NAMES: Array[String] = [
	"High Card",
	"One Pair",
	"Two Pair",
	"Three of a Kind",
	"Straight",
	"Flush",
	"Full House",
	"Four of a Kind",
	"Straight Flush",
	"Royal Flush",
]


static func evaluate_hand(cards: Array[Card]) -> Dictionary:
	if cards.size() < 5:
		push_error("evaluate_hand requires at least 5 cards, got %d" % cards.size())
		return _empty_result()

	var best: Dictionary = {}
	var combos: Array = _combinations(cards, 5)
	for combo in combos:
		var five: Array[Card] = []
		for c in combo:
			five.append(c)
		var result: Dictionary = _evaluate_five(five)
		if best.is_empty() or compare_hands(result, best) > 0:
			best = result
	return best


static func compare_hands(hand_a: Dictionary, hand_b: Dictionary) -> int:
	if hand_a.rank != hand_b.rank:
		return 1 if hand_a.rank > hand_b.rank else -1
	var tb_a: Array = hand_a.tiebreakers
	var tb_b: Array = hand_b.tiebreakers
	var limit: int = mini(tb_a.size(), tb_b.size())
	for i in range(limit):
		if tb_a[i] != tb_b[i]:
			return 1 if tb_a[i] > tb_b[i] else -1
	return 0


static func _empty_result() -> Dictionary:
	return {
		"rank": -1,
		"rank_name": "Invalid",
		"best_five": [],
		"tiebreakers": [],
	}


static func _evaluate_five(cards: Array[Card]) -> Dictionary:
	var ranks: Array[int] = []
	var suits: Array[int] = []
	for card in cards:
		ranks.append(card.rank)
		suits.append(card.suit)
	ranks.sort()
	ranks.reverse()

	var is_flush: bool = suits[0] == suits[1] and suits[1] == suits[2] and suits[2] == suits[3] and suits[3] == suits[4]
	var straight_high: int = _straight_high(ranks)
	var is_straight: bool = straight_high > 0

	var counts: Dictionary = {}
	for rank in ranks:
		counts[rank] = counts.get(rank, 0) + 1

	var groups: Array[Dictionary] = []
	for rank in counts:
		groups.append({"rank": rank, "count": counts[rank]})
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.count != b.count:
			return a.count > b.count
		return a.rank > b.rank
	)

	var rank_value: int = RANK_HIGH_CARD
	var tiebreakers: Array = []

	if is_flush and is_straight:
		if straight_high == 14:
			rank_value = RANK_ROYAL_FLUSH
		else:
			rank_value = RANK_STRAIGHT_FLUSH
		tiebreakers = [straight_high]
	elif groups[0].count == 4:
		rank_value = RANK_FOUR_KIND
		var kicker: int = _find_kicker(ranks, [groups[0].rank])
		tiebreakers = [groups[0].rank, kicker]
	elif groups[0].count == 3 and groups[1].count == 2:
		rank_value = RANK_FULL_HOUSE
		tiebreakers = [groups[0].rank, groups[1].rank]
	elif is_flush:
		rank_value = RANK_FLUSH
		tiebreakers = ranks.duplicate()
	elif is_straight:
		rank_value = RANK_STRAIGHT
		tiebreakers = [straight_high]
	elif groups[0].count == 3:
		rank_value = RANK_THREE_KIND
		tiebreakers = [groups[0].rank]
		tiebreakers.append_array(_kickers_excluding(ranks, [groups[0].rank], 2))
	elif groups[0].count == 2 and groups[1].count == 2:
		rank_value = RANK_TWO_PAIR
		var high_pair: int = maxi(groups[0].rank, groups[1].rank)
		var low_pair: int = mini(groups[0].rank, groups[1].rank)
		var pair_kicker: int = _find_kicker(ranks, [high_pair, low_pair])
		tiebreakers = [high_pair, low_pair, pair_kicker]
	elif groups[0].count == 2:
		rank_value = RANK_ONE_PAIR
		tiebreakers = [groups[0].rank]
		tiebreakers.append_array(_kickers_excluding(ranks, [groups[0].rank], 3))
	else:
		rank_value = RANK_HIGH_CARD
		tiebreakers = ranks.duplicate()

	return {
		"rank": rank_value,
		"rank_name": RANK_NAMES[rank_value],
		"best_five": cards.duplicate(),
		"tiebreakers": tiebreakers,
	}


static func _straight_high(ranks: Array[int]) -> int:
	var unique: Array[int] = []
	for rank in ranks:
		if rank not in unique:
			unique.append(rank)
	if unique.size() != 5:
		return 0
	unique.sort()

	if unique == [2, 3, 4, 5, 14]:
		return 5

	for i in range(1, 5):
		if unique[i] != unique[i - 1] + 1:
			return 0
	return unique[4]


static func _find_kicker(ranks: Array[int], excluded: Array[int]) -> int:
	for rank in ranks:
		if rank not in excluded:
			return rank
	return 0


static func _kickers_excluding(ranks: Array[int], excluded: Array[int], count: int) -> Array:
	var result: Array = []
	for rank in ranks:
		if rank in excluded:
			continue
		result.append(rank)
		if result.size() == count:
			break
	return result


static func _combinations(cards: Array[Card], choose: int) -> Array:
	var result: Array = []
	var current: Array[Card] = []
	_comb_recurse(cards, choose, 0, current, result)
	return result


static func _comb_recurse(
	cards: Array[Card],
	choose: int,
	start: int,
	current: Array[Card],
	result: Array
) -> void:
	if current.size() == choose:
		result.append(current.duplicate())
		return
	for i in range(start, cards.size()):
		current.append(cards[i])
		_comb_recurse(cards, choose, i + 1, current, result)
		current.pop_back()
