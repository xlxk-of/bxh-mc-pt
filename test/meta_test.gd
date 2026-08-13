extends Node
## Headless check for the permanent profile and the Sin Tree.
##
## This is the meta layer, so the things worth asserting are the ones that only
## show up across runs: that the tree is a well-formed dependency graph, that
## embers cannot be spent twice or spent into debt, that a locked node stays
## hidden until its prerequisite is owned, and that the whole lot survives a
## save/load round trip. A tree that quietly forgets a purchase is the single
## worst bug this system can have.
##
##   godot --headless --path . res://test/meta_test.tscn

var _checks := 0
var _failures := 0


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: ", label)


func _ready() -> void:
	print("=== Block X Hell meta test ===")
	_test_tree_shape()
	_test_purchase_rules()
	_test_reveal_rules()
	_test_bonuses()
	_test_persistence()
	print("=== %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_tree_shape() -> void:
	print("- tree shape")
	var ids := {}
	var by_branch := {}
	for node: Dictionary in SinTreeData.NODES:
		var id: String = node["id"]
		check(not ids.has(id), "node id %s is unique" % id)
		ids[id] = node
		check(int(node["cost"]) > 0, "%s costs something" % id)
		check(not String(node["name"]).is_empty(), "%s is named" % id)
		check(not String(node["description"]).is_empty(), "%s is described" % id)
		check(not String(node["effect_key"]).is_empty(), "%s has an effect key" % id)
		var branch: String = node["branch"]
		by_branch[branch] = by_branch.get(branch, 0) + 1

	check(SinTreeData.BRANCHES.size() >= 7, "at least 7 branches (got %d)" % SinTreeData.BRANCHES.size())
	# The brief was "larger than the reference", which had 22 nodes.
	check(SinTreeData.NODES.size() > 22, "tree beats the reference's 22 nodes (got %d)" % SinTreeData.NODES.size())

	for branch: Dictionary in SinTreeData.BRANCHES:
		var id: String = branch["id"]
		check(by_branch.get(id, 0) > 0, "branch %s has nodes" % id)

	# Every prerequisite must exist, sit in the same branch, and be shallower --
	# which together make cycles impossible.
	for node: Dictionary in SinTreeData.NODES:
		var req := String(node.get("requires", ""))
		if req.is_empty():
			continue
		check(ids.has(req), "%s requires a real node (%s)" % [node["id"], req])
		if ids.has(req):
			var parent: Dictionary = ids[req]
			check(parent["branch"] == node["branch"],
				"%s requires a node in its own branch" % node["id"])
			check(int(parent["tier"]) < int(node["tier"]),
				"%s requires a shallower tier" % node["id"])


func _test_purchase_rules() -> void:
	print("- purchase rules")
	Profile.reset_tree()
	Profile.embers = 0

	var root := _first_root()
	check(root != "", "there is a tier-1 node to buy")
	check(not Profile.can_buy(root), "cannot buy with no embers")
	check(not Profile.buy(root), "buying with no embers is refused")

	var cost: int = int(SinTreeData.NODES[_index_of(root)]["cost"])
	Profile.award_embers(cost)
	check(Profile.can_buy(root), "affordable once paid for")
	check(Profile.buy(root), "purchase succeeds")
	check(Profile.owns(root), "purchase is recorded")
	check(Profile.embers == 0, "purchase spends exactly the cost")
	check(not Profile.can_buy(root), "cannot buy the same node twice")
	check(not Profile.buy(root), "second purchase is refused")

	# A locked child stays locked no matter how rich you are.
	var child := _child_of(root)
	if child != "":
		Profile.reset_tree()
		Profile.award_embers(100000)
		check(not Profile.can_buy(child), "child is locked while its parent is not owned")
		check(not Profile.buy(child), "buying a locked child is refused")
		var parent_cost: int = int(SinTreeData.NODES[_index_of(root)]["cost"])
		check(Profile.embers >= parent_cost, "a refused purchase costs nothing")
		Profile.buy(root)
		check(Profile.can_buy(child), "child unlocks once its parent is owned")


func _test_reveal_rules() -> void:
	print("- reveal rules")
	Profile.reset_tree()
	var root := _first_root()
	var child := _child_of(root)
	check(Profile.revealed(root), "roots are always readable")
	if child != "":
		check(not Profile.revealed(child), "a node two steps out stays hidden")
		Profile.award_embers(100000)
		Profile.buy(root)
		check(Profile.revealed(child), "the next node up is readable once reachable")


func _test_bonuses() -> void:
	print("- bonuses")
	Profile.reset_tree()
	var keys := {}
	for node: Dictionary in SinTreeData.NODES:
		keys[node["effect_key"]] = true
	for key: String in keys:
		check(is_equal_approx(Profile.bonus(key), 0.0), "%s starts at zero" % key)
	check(is_equal_approx(Profile.bonus("no_such_effect_key"), 0.0), "unknown keys are zero, not an error")

	# Buying a whole branch must sum its shared keys rather than overwrite them.
	Profile.award_embers(1000000)
	var branch: String = String(SinTreeData.NODES[0]["branch"])
	var expected := {}
	for node: Dictionary in SinTreeData.NODES:
		if node["branch"] != branch:
			continue
		if Profile.buy(node["id"]):
			var key: String = node["effect_key"]
			expected[key] = expected.get(key, 0.0) + float(node["effect_value"])
	check(not expected.is_empty(), "bought at least one node in %s" % branch)
	for key: String in expected:
		check(is_equal_approx(Profile.bonus(key), expected[key]),
			"%s sums to %.3f (got %.3f)" % [key, expected[key], Profile.bonus(key)])


func _test_persistence() -> void:
	print("- persistence")
	Profile.reset_tree()
	Profile.award_embers(1000000)
	var bought: Array[String] = []
	for node: Dictionary in SinTreeData.NODES:
		if Profile.buy(node["id"]):
			bought.append(node["id"])
	check(bought.size() >= 7, "bought a spread of the tree (%d)" % bought.size())
	var embers_before := Profile.embers
	var sample_key := String(SinTreeData.NODES[0]["effect_key"])
	var bonus_before := Profile.bonus(sample_key)

	Profile.save_profile()
	Profile.load_profile()
	check(Profile.embers == embers_before, "embers survive a round trip")
	check(is_equal_approx(Profile.bonus(sample_key), bonus_before),
		"bonuses survive a round trip")
	var all_kept := true
	for id in bought:
		if not Profile.owns(id):
			all_kept = false
	check(all_kept, "every purchase survives a round trip")

	# Embers are the whole economy, so a run payout has to be positive and has to
	# scale with how well the run went.
	var small := Profile.embers_for_run(500, 1)
	var large := Profile.embers_for_run(90000, 12)
	check(small >= 1, "even a bad run pays something (%d)" % small)
	check(large > small, "a better run pays more (%d > %d)" % [large, small])

	# reset_tree() refunds nothing by design, so zero the embers too. Otherwise
	# this test leaves a million-ember profile on disk for every later harness.
	Profile.reset_tree()
	Profile.embers = 0
	Profile.save_profile()
	check(Profile.embers == 0, "the test leaves a clean profile behind")


# ==========================================================================
#  Helpers
# ==========================================================================
func _first_root() -> String:
	for node: Dictionary in SinTreeData.NODES:
		if String(node.get("requires", "")).is_empty():
			return node["id"]
	return ""


func _child_of(parent_id: String) -> String:
	for node: Dictionary in SinTreeData.NODES:
		if String(node.get("requires", "")) == parent_id:
			return node["id"]
	return ""


func _index_of(node_id: String) -> int:
	for i in SinTreeData.NODES.size():
		if SinTreeData.NODES[i]["id"] == node_id:
			return i
	return 0
