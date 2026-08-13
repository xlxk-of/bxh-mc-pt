extends Node
## Persistence: settings, high score, player progress and the mid-run save.
## Everything lives under user:// so it works identically on desktop and mobile.

const SETTINGS_PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://player_data.json"
const RUN_PATH := "user://saved_run.json"

signal settings_changed

var music_volume := 0.5
var sfx_volume := 0.7
var fullscreen := false
var crt_filter := true
var screen_shake := 1.0
## 0 = Default (Block Blast style: the piece tracks finger motion, amplified).
## 1 = Direct (the piece sits at the finger, 1:1).
var placement_mode := 0
## How far the piece travels per unit of finger travel in Default placement.
## 1.0 is finger-accurate; higher lets a short flick from the tray cross the
## board at the cost of precision. Only used on touch.
var drag_gain := 1.5
## 0 = auto-detect, 1 = force the touch layout, 2 = force the desktop layout.
## An escape hatch for browsers that lie about their pointer hardware -- a
## home-screen PWA can report a desktop user agent and get 40px buttons.
var touch_override := 0
var haptics := true
var control_hint_shown := false
var high_score := 0
var completed_contracts: Array = []


func _ready() -> void:
	load_settings()
	load_progress()


# ------------------------------------------------------------------ settings
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	music_volume = cf.get_value("audio", "music", music_volume)
	sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	crt_filter = cf.get_value("display", "crt", crt_filter)
	screen_shake = cf.get_value("display", "shake", screen_shake)
	haptics = cf.get_value("input", "haptics", haptics)
	placement_mode = cf.get_value("input", "placement_mode", placement_mode)
	drag_gain = clampf(cf.get_value("input", "drag_gain", drag_gain), 1.0, 3.0)
	touch_override = cf.get_value("input", "touch_override", touch_override)
	control_hint_shown = cf.get_value("input", "hint_shown", control_hint_shown)
	high_score = cf.get_value("score", "high", high_score)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "crt", crt_filter)
	cf.set_value("display", "shake", screen_shake)
	cf.set_value("input", "haptics", haptics)
	cf.set_value("input", "placement_mode", placement_mode)
	cf.set_value("input", "drag_gain", drag_gain)
	cf.set_value("input", "touch_override", touch_override)
	cf.set_value("input", "hint_shown", control_hint_shown)
	cf.set_value("score", "high", high_score)
	cf.save(SETTINGS_PATH)
	settings_changed.emit()


func submit_score(score: int) -> bool:
	if score > high_score:
		high_score = score
		save_settings()
		return true
	return false


# ------------------------------------------------------------------ progress
func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		completed_contracts = data.get("completed_contracts", [])


func save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"completed_contracts": completed_contracts}, "\t"))
	f.close()


func mark_contract_completed(contract_name: String) -> void:
	if not completed_contracts.has(contract_name):
		completed_contracts.append(contract_name)
		save_progress()


# ------------------------------------------------------------------ run save
func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


func save_run(data: Dictionary) -> void:
	var f := FileAccess.open(RUN_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write run save")
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_run() -> Dictionary:
	if not has_run():
		return {}
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(raw)
	if data is Dictionary:
		return data
	delete_run()
	return {}


func delete_run() -> void:
	if has_run():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
		# globalize_path is a no-op inside exported builds for user://, so retry
		# through DirAccess bound to the user directory.
		var d := DirAccess.open("user://")
		if d and d.file_exists("saved_run.json"):
			d.remove("saved_run.json")
