extends Node
## E2E network test driver. Lives directly under /root so it survives scene
## changes. role = "host": hosts on E2E_PORT, starts the game when a client
## joins, auto-plays check/call. role = "client": joins localhost and does the
## same. Both verify hole-card privacy and print E2E markers for the harness.

const E2E_PORT := 8910

var role: String = "host"

var _snap_serial := 0
var _done := false
var _started := false
var _audited_snapshots := 0
var _privacy_leaks := 0
var _sample_printed := false


func _ready() -> void:
	NetGame.state_updated.connect(_on_state)
	get_tree().create_timer(60.0).timeout.connect(_on_watchdog)

	if role == "host":
		var result: Dictionary = Net.create_server(E2E_PORT)
		if not result.ok:
			print("E2E_FAIL: %s" % result.error)
			get_tree().quit(1)
			return
		Net.players_changed.connect(_maybe_start)
		print("[e2e] host ready, waiting for client...")
	else:
		Net.join_failed.connect(func(reason: String) -> void:
			print("E2E_FAIL: join failed: %s" % reason)
			get_tree().quit(1))
		var result: Dictionary = Net.join_server("127.0.0.1", E2E_PORT)
		if not result.ok:
			print("E2E_FAIL: %s" % result.error)
			get_tree().quit(1)
			return
		print("[e2e] client connecting...")


func _maybe_start() -> void:
	if _started or Net.players.size() < 2:
		return
	_started = true
	print("[e2e] %d players in lobby, starting game" % Net.players.size())
	await get_tree().create_timer(0.5).timeout
	NetGame.host_begin_session()


func _on_state(snap: Dictionary) -> void:
	if _done:
		return
	_snap_serial += 1

	# Audit EVERY pre-showdown snapshot exactly as it arrived over the wire:
	# opponent cards must be "??" in the payload itself (masked host-side).
	if not snap.hand_over:
		_audited_snapshots += 1
		for entry in snap.players:
			if entry.seat == snap.your_seat:
				continue
			for card in entry.cards:
				if card != "??":
					_privacy_leaks += 1
					print("E2E_PRIVACY_LEAK: seat %d card '%s' visible in phase %s!" % [entry.seat, card, snap.phase])
		if not _sample_printed:
			_sample_printed = true
			var dump: Array = []
			for entry in snap.players:
				dump.append("seat %d cards=%s" % [entry.seat, str(entry.cards)])
			print("[e2e] wire payload sample (my seat %d): %s" % [snap.your_seat, " | ".join(dump)])

	if snap.hand_over:
		_done = true
		print("[e2e] hand finished: reason=%s payouts=%s" % [snap.results.get("reason", "?"), str(snap.results.get("payouts", {}))])
		print("E2E_PRIVACY_%s: %d pre-showdown snapshots audited, %d leaks" % [
			"FAIL" if _privacy_leaks > 0 else "OK", _audited_snapshots, _privacy_leaks,
		])
		print("E2E_%s_DONE" % role.to_upper())
		var delay := 1.5 if role == "host" else 0.5
		await get_tree().create_timer(delay).timeout
		get_tree().quit(0)
		return

	if snap.current_seat == snap.your_seat and not snap.legal_actions.is_empty():
		var serial := _snap_serial
		await get_tree().create_timer(0.2).timeout
		if _done or serial != _snap_serial:
			return
		var action: String = "check" if "check" in snap.legal_actions else "call"
		print("[e2e] my turn (seat %d), acting: %s" % [snap.your_seat, action])
		NetGame.send_action(action)


func _on_watchdog() -> void:
	if not _done:
		print("E2E_FAIL: 60s timeout, phase=%s" % str(NetGame.latest_snapshot.get("phase", "none")))
		get_tree().quit(1)
