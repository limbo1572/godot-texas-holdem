extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== test_blind_schedule ===")
	_test_schedule_table()
	_test_level_zero_at_start()
	_test_level_held_during_hand_applied_between()
	_test_session_clock_not_reset_between_hands()
	_test_final_level_holds()
	_test_short_stack_blind_all_in()
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


## End the current hand quickly with legal actions (fold when possible).
func _finish_hand(game: GameState) -> void:
	var safety := 0
	while not game.hand_over and safety < 200:
		safety += 1
		if game.is_runout_phase:
			game.advance_runout()
			continue
		var legal: Array[String] = game.get_legal_actions(game.current_player)
		if legal.is_empty():
			break
		if "fold" in legal:
			game.player_action(game.current_player, "fold")
		elif "check" in legal:
			game.player_action(game.current_player, "check")
		else:
			game.player_action(game.current_player, "call")


func _test_schedule_table() -> void:
	_assert_eq(BlindSchedule.level_count() >= 8, true, "schedule has 8+ levels (%d)" % BlindSchedule.level_count())
	var increasing := true
	var bb_double := true
	for i in range(BlindSchedule.level_count()):
		var lvl: Dictionary = BlindSchedule.level(i)
		if lvl.bb != lvl.sb * 2:
			bb_double = false
		if i > 0 and lvl.sb <= BlindSchedule.level(i - 1).sb:
			increasing = false
	_assert_eq(increasing, true, "blinds strictly increase per level")
	_assert_eq(bb_double, true, "bb == 2*sb on every level")
	_assert_eq(BlindSchedule.level_for_elapsed(0.0), 0, "elapsed 0 -> level 0")
	_assert_eq(BlindSchedule.level_for_elapsed(299.9), 0, "elapsed 299.9 -> still level 0")
	_assert_eq(BlindSchedule.level_for_elapsed(300.0), 1, "elapsed 300 -> level 1")
	_assert_eq(BlindSchedule.level_for_elapsed(601.0), 2, "elapsed 601 -> level 2")
	_assert_eq(BlindSchedule.time_remaining(280.0), 20.0, "time_remaining 20s before level 2")


func _test_level_zero_at_start() -> void:
	var game := GameState.new(3)
	game.start_hand()
	_assert_eq(game.current_level, 0, "fresh session starts at level 0")
	_assert_eq(game.small_blind, 10, "level 0 sb = 10")
	_assert_eq(game.big_blind, 20, "level 0 bb = 20")
	_assert_eq(game.player_committed[game.bb_player()], 20, "bb posted 20")


func _test_level_held_during_hand_applied_between() -> void:
	var game := GameState.new(3)
	game.start_hand()
	## Level time expires mid-hand: blinds must NOT change until the next hand.
	game.time_offset_sec = 301.0
	_assert_eq(game.small_blind, 10, "mid-hand: sb still 10 after level time expired")
	_assert_eq(game.current_level, 0, "mid-hand: level not bumped")
	_finish_hand(game)
	_assert_eq(game.hand_over, true, "hand finished cleanly")
	game.start_hand()
	_assert_eq(game.current_level, 1, "next hand: level 1 applied")
	_assert_eq(game.small_blind, 15, "next hand: sb = 15")
	_assert_eq(game.big_blind, 30, "next hand: bb = 30")
	_assert_eq(game.player_committed[game.bb_player()], 30, "next hand: bb posted 30")


func _test_session_clock_not_reset_between_hands() -> void:
	var game := GameState.new(3)
	game.start_hand()
	_finish_hand(game)
	game.time_offset_sec = 301.0
	game.start_hand()
	_assert_eq(game.current_level, 1, "clock measured from session start, not per hand")
	_finish_hand(game)
	game.time_offset_sec = 601.0
	game.start_hand()
	_assert_eq(game.current_level, 2, "level keeps advancing on the same session clock")
	_assert_eq(game.big_blind, 50, "level 2 bb = 50")


func _test_final_level_holds() -> void:
	var game := GameState.new(2)
	game.time_offset_sec = 999999.0
	game.start_hand()
	var last: int = BlindSchedule.level_count() - 1
	_assert_eq(game.current_level, last, "way past schedule -> final level held")
	_assert_eq(game.big_blind, BlindSchedule.level(last).bb, "final level bb applied")
	_assert_eq(game.level_time_remaining(), -1.0, "no countdown on final level")


func _test_short_stack_blind_all_in() -> void:
	var game := GameState.new(3, 0)
	game.player_stacks = {0: 1000, 1: 1000, 2: 15} ## seat 2 = BB with stack < bb
	game.start_hand()
	_assert_eq(game.all_in[2], true, "short BB is all-in on blind post")
	_assert_eq(game.player_committed[2], 15, "short BB posted whole stack")
	_assert_eq(game.current_bet, 20, "facing bet is still the full BB")
	_assert_eq(game.current_player, 0, "action starts normally at UTG")
	_finish_hand(game)
	_assert_eq(game.hand_over, true, "hand with short-blind all-in completes")
	var total: int = game.player_stacks[0] + game.player_stacks[1] + game.player_stacks[2]
	_assert_eq(total, 2015, "chips conserved with short blind")
