class_name Card
extends RefCounted

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

var suit: Suit
var rank: int ## 2-14, where 11=J, 12=Q, 13=K, 14=A

const SUIT_CHARS: Dictionary = {
	Suit.HEARTS: "h",
	Suit.DIAMONDS: "d",
	Suit.CLUBS: "c",
	Suit.SPADES: "s",
}

const CHAR_TO_SUIT: Dictionary = {
	"h": Suit.HEARTS,
	"d": Suit.DIAMONDS,
	"c": Suit.CLUBS,
	"s": Suit.SPADES,
}


func _init(p_suit: Suit = Suit.HEARTS, p_rank: int = 2) -> void:
	suit = p_suit
	rank = p_rank


static func from_notation(notation: String) -> Card:
	var rank_part: String = notation.substr(0, notation.length() - 1)
	var suit_char: String = notation.substr(notation.length() - 1, 1).to_lower()
	var parsed_rank: int
	match rank_part.to_upper():
		"A": parsed_rank = 14
		"K": parsed_rank = 13
		"Q": parsed_rank = 12
		"J": parsed_rank = 11
		"T", "10": parsed_rank = 10
		_: parsed_rank = int(rank_part)
	return Card.new(CHAR_TO_SUIT[suit_char], parsed_rank)


func rank_char() -> String:
	match rank:
		14: return "A"
		13: return "K"
		12: return "Q"
		11: return "J"
		10: return "T"
		_: return str(rank)


func _to_string() -> String:
	return "%s%s" % [rank_char(), SUIT_CHARS[suit]]
