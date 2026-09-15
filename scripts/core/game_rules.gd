extends Node
## Раундовая логика в стиле competitive (набросок под CS2-подобный режим).

signal round_started(round_no: int)
signal round_ended(winner: String, reason: String)
signal money_changed(peer_id: int, amount: int)
signal kill(killer: int, victim: int, weapon: String, headshot: bool)

enum Phase { FREEZE, LIVE, POST_ROUND, MATCH_OVER }

const START_MONEY := 800
const MAX_MONEY := 16000
const KILL_REWARD := 300
const HEADSHOT_BONUS := 100
const LOSS_BONUS_BASE := 1400
const LOSS_BONUS_MAX := 2900
const WIN_REWARD := 3250
const ROUND_TIME := 115.0
const FREEZE_TIME := 15.0
const PLANT_TIME := 3.0
const DEFUSE_TIME := 5.0
const BOMB_TIMER := 40.0
const ROUNDS_TO_WIN := 13

var phase: int = Phase.FREEZE
var round_no := 1
var score := {"T": 0, "CT": 0}
var loss_streak := {"T": 0, "CT": 0}
var money := {}          # peer_id -> int
var alive := {}          # peer_id -> bool
var phase_timer := 0.0


func register_player(peer_id: int, team: String) -> void:
	money[peer_id] = START_MONEY
	alive[peer_id] = true
	money_changed.emit(peer_id, START_MONEY)


func begin_round() -> void:
	phase = Phase.FREEZE
	phase_timer = FREEZE_TIME
	for id in alive:
		alive[id] = true
	round_started.emit(round_no)


func on_death(peer_id: int, killer_id: int, weapon: String, headshot: bool) -> void:
	alive[peer_id] = false
	killer_id = killer_id
	kill.emit(killer_id, peer_id, weapon, headshot)
	if killer_id >= 1:
		_award(killer_id, KILL_REWARD + (HEADSHOT_BONUS if headshot else 0))
	var dead := _count_alive()
	if dead["T"] == 0 or dead["CT"] == 0:
		end_round("CT" if dead["T"] == 0 else "T", "elimination")


func end_round(winner: String, reason: String) -> void:
	phase = Phase.POST_ROUND
	phase_timer = 5.0
	score[winner] = int(score.get(winner, 0)) + 1
	var loser := "T" if winner == "CT" else "CT"
	loss_streak[loser] = mini(int(loss_streak.get(loser, 0)) + 1, 4)
	loss_streak[winner] = 0
	for id in money:
		var team := _team_of(id)
		if team == winner:
			_award(id, WIN_REWARD)
		else:
			_award(id, LOSS_BONUS_BASE + 300 * int(loss_streak.get(loser, 0)))
	round_ended.emit(winner, reason)
	if score[winner] >= ROUNDS_TO_WIN:
		phase = Phase.MATCH_OVER


func can_buy(peer_id: int, price: int) -> bool:
	return int(money.get(peer_id, 0)) >= price


func spend(peer_id: int, price: int) -> bool:
	if not can_buy(peer_id, price):
		return false
	money[peer_id] = int(money[peer_id]) - price
	money_changed.emit(peer_id, money[peer_id])
	return true


func _award(peer_id: int, amount: int) -> void:
	money[peer_id] = mini(int(money.get(peer_id, 0)) + amount, MAX_MONEY)
	money_changed.emit(peer_id, money[peer_id])


func _count_alive() -> Dictionary:
	var out := {"T": 0, "CT": 0}
	for id in alive:
		if alive[id]:
			var t := _team_of(id)
			out[t] = int(out[t]) + 1
	return out


func _team_of(_peer_id: int) -> String:
	# TODO: реальный маппинг peer -> team из лобби
	return "CT"
