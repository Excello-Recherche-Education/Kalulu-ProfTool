class_name ProfToolSave
extends RefCounted
## The Prof Tool's session state: the language last edited and the main menu tab.
##
## Stored as a plain ConfigFile. It used to be a .tres resource, and a resource
## file names its script by path: when prof_tool_save.gd moved, every existing
## save stopped loading, and Godot logged four errors before the menu could
## start a fresh one. A ConfigFile depends on no script, so moving code can no
## longer break it.

const PATH: String = "user://prof_tool_settings.cfg"
## The resource the state used to be saved as. Read once, as text, to carry the
## user's choices over; never written, and left where it is.
const LEGACY_PATH: String = "user://prof_tool_save.tres"
const SECTION: String = "session"

var selected_language: String = ""
## The main menu tab to reopen on, so returning from an editor lands where the
## user left.
var main_menu_selected_tab: int = 0
## Each language's pack folder outside user://, the one it was last opened from
## or saved to, so the open and save dialogs start there.
var pack_folders: Dictionary[String, String] = {}


## The saved state; else the legacy one carried over; else a fresh one.
static func load_or_create() -> ProfToolSave:
	var state: ProfToolSave = ProfToolSave.new()
	if FileAccess.file_exists(PATH):
		var config: ConfigFile = ConfigFile.new()
		var error: Error = config.load(PATH)
		if error == OK:
			state.selected_language = str(config.get_value(SECTION, "selected_language", ""))
			state.main_menu_selected_tab = int(config.get_value(SECTION, "main_menu_selected_tab", 0))
			var folders: Variant = config.get_value(SECTION, "pack_folders", {})
			if folders is Dictionary:
				for language: Variant in folders:
					state.pack_folders[str(language)] = str(folders[language])
			return state
		Log.warn("ProfToolSave: %s could not be read (%s), starting a new one" % [PATH, error_string(error)])
	elif FileAccess.file_exists(LEGACY_PATH):
		state._read_legacy(FileAccess.get_file_as_string(LEGACY_PATH))
		Log.info("ProfToolSave: carried the session over from %s (language \"%s\")" % [LEGACY_PATH, state.selected_language])
	state.save()
	return state


func save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, "selected_language", selected_language)
	config.set_value(SECTION, "main_menu_selected_tab", main_menu_selected_tab)
	config.set_value(SECTION, "pack_folders", pack_folders)
	var error: Error = config.save(PATH)
	if error != OK:
		Log.error("ProfToolSave: cannot write %s (%s)" % [PATH, error_string(error)])


## Picks the two values out of the old .tres as text. Loading it as a resource
## is exactly what fails: it names a script path that may no longer exist.
func _read_legacy(text: String) -> void:
	var language: RegExMatch = RegEx.create_from_string('(?m)^selected_language = "(.*)"$').search(text)
	if language:
		selected_language = language.get_string(1).c_unescape()
	var tab: RegExMatch = RegEx.create_from_string("(?m)^main_menu_selected_tab = (\\d+)$").search(text)
	if tab:
		main_menu_selected_tab = tab.get_string(1).to_int()
