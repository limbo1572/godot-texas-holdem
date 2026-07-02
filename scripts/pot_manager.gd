class_name PotManager
extends RefCounted
## Builds main/side pots from per-hand chip commitments and distributes them.


## commitments: pid -> total chips committed this hand.
## folded: pid -> bool.
## Returns { "pots": Array of {amount, eligible}, "refunds": pid -> int }.
## Pots are ordered main pot first, then side pots.
static func build_pots(commitments: Dictionary, folded: Dictionary) -> Dictionary:
	var adjusted: Dictionary = {}
	for pid in commitments:
		adjusted[pid] = commitments[pid]

	# Uncalled excess: the single top committer gets back whatever nobody matched.
	var refunds: Dictionary = {}
	var top_pid: int = -1
	for pid in adjusted:
		if top_pid == -1 or adjusted[pid] > adjusted[top_pid]:
			top_pid = pid
	var second_highest: int = 0
	for pid in adjusted:
		if pid != top_pid:
			second_highest = maxi(second_highest, adjusted[pid])
	if top_pid != -1 and adjusted[top_pid] > second_highest:
		refunds[top_pid] = adjusted[top_pid] - second_highest
		adjusted[top_pid] = second_highest

	# Pot levels are the distinct commitment amounts of live players.
	var levels: Array = []
	for pid in adjusted:
		if not folded.get(pid, false) and adjusted[pid] > 0 and adjusted[pid] not in levels:
			levels.append(adjusted[pid])
	levels.sort()

	var pots: Array = []
	var prev_level: int = 0
	for level in levels:
		var amount: int = 0
		for pid in adjusted:
			amount += maxi(0, mini(adjusted[pid], level) - prev_level)
		var eligible: Array = []
		for pid in adjusted:
			if not folded.get(pid, false) and adjusted[pid] >= level:
				eligible.append(pid)
		if amount > 0:
			pots.append({"amount": amount, "eligible": eligible})
		prev_level = level

	# Conservation guard: any leftover chips (theoretical edge) go to the last pot.
	var total_adjusted: int = 0
	for pid in adjusted:
		total_adjusted += adjusted[pid]
	var assigned: int = 0
	for pot in pots:
		assigned += pot.amount
	if not pots.is_empty() and total_adjusted > assigned:
		pots[-1].amount += total_adjusted - assigned

	return {"pots": pots, "refunds": refunds}


## pots: output of build_pots. hands: pid -> evaluated hand (live players only).
## Returns pid -> total payout. Also annotates each pot with a "winners" array.
static func distribute(pots: Array, hands: Dictionary) -> Dictionary:
	var payouts: Dictionary = {}
	for pot in pots:
		var contenders: Array = []
		for pid in pot.eligible:
			if hands.has(pid):
				contenders.append(pid)
		if contenders.is_empty():
			pot["winners"] = []
			continue

		var winners: Array = [contenders[0]]
		for i in range(1, contenders.size()):
			var pid: int = contenders[i]
			var cmp: int = HandEvaluator.compare_hands(hands[pid], hands[winners[0]])
			if cmp > 0:
				winners = [pid]
			elif cmp == 0:
				winners.append(pid)
		pot["winners"] = winners

		var share: int = pot.amount / winners.size()
		var remainder: int = pot.amount % winners.size()
		for i in range(winners.size()):
			var pay: int = share + (1 if i < remainder else 0)
			payouts[winners[i]] = payouts.get(winners[i], 0) + pay
	return payouts
