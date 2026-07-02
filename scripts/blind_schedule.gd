class_name BlindSchedule
extends RefCounted
## Hardcoded tournament blind progression (~x1.5 per level, 5 min each).
## When the schedule runs out, the final level holds indefinitely.

const LEVELS: Array = [
	{"sb": 10, "bb": 20, "duration_sec": 300},
	{"sb": 15, "bb": 30, "duration_sec": 300},
	{"sb": 25, "bb": 50, "duration_sec": 300},
	{"sb": 40, "bb": 80, "duration_sec": 300},
	{"sb": 60, "bb": 120, "duration_sec": 300},
	{"sb": 100, "bb": 200, "duration_sec": 300},
	{"sb": 150, "bb": 300, "duration_sec": 300},
	{"sb": 250, "bb": 500, "duration_sec": 300},
	{"sb": 400, "bb": 800, "duration_sec": 300},
	{"sb": 600, "bb": 1200, "duration_sec": 300},
]


static func level_count() -> int:
	return LEVELS.size()


static func level(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


## Level index for a given time since session start (clamped to final level).
static func level_for_elapsed(elapsed_sec: float) -> int:
	var t := elapsed_sec
	for i in range(LEVELS.size()):
		if t < LEVELS[i].duration_sec:
			return i
		t -= LEVELS[i].duration_sec
	return LEVELS.size() - 1


## Seconds until the next level, or -1.0 when the final level is reached.
static func time_remaining(elapsed_sec: float) -> float:
	var t := elapsed_sec
	for i in range(LEVELS.size()):
		if t < LEVELS[i].duration_sec:
			if i == LEVELS.size() - 1:
				return -1.0
			return LEVELS[i].duration_sec - t
		t -= LEVELS[i].duration_sec
	return -1.0
