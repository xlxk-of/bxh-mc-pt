extends Node
## Permanent progress: Soul Embers and the Sin Tree. This is the only state that
## outlives a run, so every change is written straight to disk instead of
## waiting for a checkpoint a crash could eat.
##
## The tree itself lives in SinTreeData; this node owns what is owned, what it
## cost, and what the owned effects add up to. Nothing here knows how a bonus is
## spent - game_session.gd asks bonus("some_key") and gets a number.

const PROFILE_PATH := "user://profile.json"

## embers_for_run() tuning. Deliberately stingy, in the spirit of the reference:
## a first run should buy a tier-1 node and nothing else, and a tier-5 node
## should cost a season of runs.
const EMBERS_PER_ROUND := 1
const EMBERS_PER_BOSS := 8
## Boss rounds are every 5th round, matching the cadence in game_session.gd.
const BOSS_ROUND_INTERVAL := 5
const EMBERS_PER_SCORE := 8000
const EMBERS_SCORE_CAP := 25

signal embers_changed(total: int)
signal node_purchased(node_id: String)

## Assigning this directly is legitimate - the HUD tracks embers_changed, so the
## setter emits rather than trusting every caller to remember.
var embers: int = 0:
	set(value):
		var next := maxi(0, value)
		if next == embers:
			return
		embers = next
		embers_changed.emit(embers)

## node_id -> true. A set, so an ownership check is a hash probe, not a scan.
var _owned := {}
## effect_key -> summed effect_value of every owned node carrying that key.
## bonus() is called per placement, so the sum is cached and only ever touched
## when a purchase lands or the profile is reloaded.
var _totals := {}


func _ready() -> void:
	load_profile()


# ==========================================================================
#  Sin Tree
# ==========================================================================
## Deliberately not called has_node(): Node already binds that as a scene-tree
## path lookup, and a script cannot override it. A tree node id is not a
## NodePath and must never be resolved as one.
func owns(node_id: String) -> bool:
	return _owned.has(node_id)


func _mark_owned(node_id: String) -> void:
	_owned[node_id] = true


func _forget_owned() -> void:
	_owned.clear()


func can_buy(node_id: String) -> bool:
	var node := SinTreeData.node(node_id)
	if node.is_empty() or _owned.has(node_id):
		return false
	if embers < int(node["cost"]):
		return false
	var req := String(node["requires"])
	return req.is_empty() or _owned.has(req)


func buy(node_id: String) -> bool:
	if not can_buy(node_id):
		return false
	var node := SinTreeData.node(node_id)
	embers -= int(node["cost"])
	_mark_owned(node_id)
	_credit(node)
	save_profile()
	node_purchased.emit(node_id)
	return true


## Whether a node's name and description may be shown. One step past the
## frontier is readable so the next purchase can tempt; anything deeper stays a
## rumour until its prerequisite is paid for.
func revealed(node_id: String) -> bool:
	if _owned.has(node_id):
		return true
	var node := SinTreeData.node(node_id)
	if node.is_empty():
		return false
	var req := String(node["requires"])
	return req.is_empty() or _owned.has(req)


func bonus(effect_key: String) -> float:
	return _totals.get(effect_key, 0.0)


func nodes_in_branch(branch_id: String) -> Array[Dictionary]:
	return SinTreeData.nodes_in_branch(branch_id)


## Respec: unlearn the whole tree and hand back every ember it cost. A reset
## that simply burned the spend would be a button nobody could ever press.
func reset_tree() -> void:
	var refund := 0
	for node_id: String in _owned:
		refund += int(SinTreeData.node(node_id).get("cost", 0))
	_forget_owned()
	_totals.clear()
	embers += refund
	save_profile()


# ==========================================================================
#  Embers
# ==========================================================================
func award_embers(amount: int) -> void:
	if amount <= 0:
		return
	embers += amount
	save_profile()


## Payout for a finished run. Rounds are the spine of it - score only tops it
## up, and caps out - because score inflates with the tree while rounds do not.
## `rounds` is game_session.round_count, which starts at 1, so the round you
## died in does not pay.
func embers_for_run(score: int, rounds: int) -> int:
	var survived := maxi(0, rounds - 1)
	var bosses := survived / BOSS_ROUND_INTERVAL
	var from_score := mini(maxi(0, score) / EMBERS_PER_SCORE, EMBERS_SCORE_CAP)
	var total := survived * EMBERS_PER_ROUND + bosses * EMBERS_PER_BOSS + from_score
	# Every run pays something, or a bad first run leaves the tree unreachable.
	return maxi(1, total)


# ==========================================================================
#  Persistence
# ==========================================================================
## Missing file, unreadable file, corrupt JSON and ids from an older tree are
## all the same thing here: start from whatever is provably true and carry on.
## A profile that refuses to load would cost a player every run they ever made.
func load_profile() -> void:
	_forget_owned()
	embers = 0
	var data: Variant = _read_json()
	if data is Dictionary:
		var saved: Dictionary = data
		var raw_embers: Variant = saved.get("embers", 0)
		if raw_embers is float or raw_embers is int:
			embers = maxi(0, int(raw_embers))
		var raw_nodes: Variant = saved.get("nodes", [])
		if raw_nodes is Array:
			for raw_id: Variant in raw_nodes:
				# An unknown id is a node that was renamed or cut; trusting it
				# would grant a bonus no node in the tree can explain.
				if raw_id is String and not SinTreeData.node(raw_id).is_empty():
					_mark_owned(raw_id)
	_rebuild_totals()


func save_profile() -> void:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write the profile")
		return
	f.store_string(JSON.stringify({"embers": embers, "nodes": _owned.keys()}, "\t"))
	f.close()


func _read_json() -> Variant:
	if not FileAccess.file_exists(PROFILE_PATH):
		return null
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return null
	var raw := f.get_as_text()
	f.close()
	return JSON.parse_string(raw)


# ==========================================================================
#  Effect totals
# ==========================================================================
func _credit(node: Dictionary) -> void:
	var key := String(node["effect_key"])
	_totals[key] = float(_totals.get(key, 0.0)) + float(node["effect_value"])


func _rebuild_totals() -> void:
	_totals.clear()
	for node: Dictionary in SinTreeData.NODES:
		if _owned.has(node["id"]):
			_credit(node)
