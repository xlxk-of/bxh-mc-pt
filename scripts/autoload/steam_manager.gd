extends Node
## Steam integration for the GodotSteam ("Steam Edition") build of Godot 4.7.
##
## Every call is guarded: in a vanilla Godot editor, or when Steam is not
## running, this degrades to a silent no-op so the game still boots and plays.
## Set `app_id` to your real AppID before shipping -- 480 (Spacewar) is the
## public test app and is only useful for local smoke tests.

signal overlay_toggled(active: bool)

const APP_ID_FILE := "res://steam_appid.txt"
const DEFAULT_APP_ID := 480

var available := false
var initialized := false
var app_id := DEFAULT_APP_ID
var steam_name := ""
var _steam: Object = null
var _needs_manual_callbacks := true
var _pending_stat_store := false

## Achievement API names -> the in-game condition that unlocks them. Create
## these in the Steamworks partner site with matching API names.
const ACHIEVEMENTS := {
	"FIRST_BLOOD": "Clear your first line",
	"COMBO_10": "Reach a x10 combo",
	"COMBO_25": "Reach a x25 combo",
	"PERFECTIONIST": "Trigger a Perfectionist board clear",
	"BOSS_SURVIVOR": "Survive a Giga Boss round",
	"DEAL_MAKER": "Sign a contract with Lucifer",
	"FULL_HOUSE": "Fill every card slot",
	"SCORE_100K": "Score 100,000 in a single run",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		print_rich("[color=gray]Steam singleton not present - running without Steamworks.[/color]")
		set_process(false)
		return
	_steam = Engine.get_singleton("Steam")
	available = true
	_read_app_id()
	_initialize()


func _read_app_id() -> void:
	if FileAccess.file_exists(APP_ID_FILE):
		var f := FileAccess.open(APP_ID_FILE, FileAccess.READ)
		if f:
			var txt := f.get_as_text().strip_edges()
			f.close()
			if txt.is_valid_int():
				app_id = int(txt)


func _initialize() -> void:
	# GodotSteam has changed steamInitEx's signature across releases, so match
	# whatever this build actually exposes instead of guessing.
	var arg_count := -1
	var method := ""
	for m in _steam.get_method_list():
		if m.get("name", "") == "steamInitEx":
			method = "steamInitEx"
			arg_count = (m.get("args", []) as Array).size()
			break
	if method.is_empty():
		for m in _steam.get_method_list():
			if m.get("name", "") == "steamInit":
				method = "steamInit"
				arg_count = (m.get("args", []) as Array).size()
				break
	if method.is_empty():
		push_warning("Steam singleton found but no init method; skipping.")
		available = false
		return

	var args: Array = []
	match arg_count:
		0: args = []
		1: args = [app_id]
		2: args = [app_id, true]
		_: args = [true, app_id, true]

	var result: Variant = _steam.callv(method, args)
	var status := 0
	if result is Dictionary:
		status = int(result.get("status", 0))
		if status != 0:
			print_rich("[color=orange]Steam init: %s[/color]" % str(result.get("verbal", status)))
	initialized = status == 0

	if initialized:
		_needs_manual_callbacks = arg_count < 2
		if _steam.has_method("getPersonaName"):
			steam_name = str(_steam.call("getPersonaName"))
		if _steam.has_method("requestCurrentStats"):
			_steam.call("requestCurrentStats")
		if _steam.has_signal("overlay_toggled"):
			_steam.connect("overlay_toggled", _on_overlay_toggled)
		print_rich("[color=green]Steam ready (AppID %d)%s[/color]" %
			[app_id, "" if steam_name.is_empty() else " - " + steam_name])
	set_process(initialized and _needs_manual_callbacks)


func _process(_delta: float) -> void:
	if initialized and _needs_manual_callbacks and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")


func _on_overlay_toggled(active: bool, _user_initiated: bool = false, _api_call: int = 0) -> void:
	overlay_toggled.emit(active)
	# Pause the run while the Steam overlay covers the window.
	get_tree().paused = active


# ------------------------------------------------------------------- API
func unlock(achievement: String) -> void:
	if not initialized or not ACHIEVEMENTS.has(achievement):
		return
	if _steam.has_method("setAchievement"):
		_steam.call("setAchievement", achievement)
		_pending_stat_store = true


func set_stat(stat: String, value: int) -> void:
	if not initialized:
		return
	if _steam.has_method("setStatInt"):
		_steam.call("setStatInt", stat, value)
		_pending_stat_store = true


## Batch stat/achievement writes; call at natural break points, not per frame.
func flush() -> void:
	if initialized and _pending_stat_store and _steam.has_method("storeStats"):
		_steam.call("storeStats")
		_pending_stat_store = false


func set_rich_presence(key: String, value: String) -> void:
	if initialized and _steam.has_method("setRichPresence"):
		_steam.call("setRichPresence", key, value)


func shutdown() -> void:
	if initialized:
		flush()
		if _steam.has_method("steamShutdown"):
			_steam.call("steamShutdown")
		initialized = false
