class_name Deck
extends RefCounted

var _cards: Array[Card] = []


func _init() -> void:
	reset()


func reset() -> void:
	_cards.clear()
	for suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS, Card.Suit.SPADES]:
		for rank in range(2, 15):
			_cards.append(Card.new(suit, rank))


func shuffle() -> void:
	_cards.shuffle()


func deal(n: int) -> Array[Card]:
	var dealt: Array[Card] = []
	for _i in range(n):
		if _cards.is_empty():
			break
		dealt.append(_cards.pop_front())
	return dealt


func cards_remaining() -> int:
	return _cards.size()
