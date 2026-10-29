extends Control

enum FileCheckResult {
	OK,
	ERROR_NOT_FOUND,
	ERROR_CASE_MISMATCH
}

const BASE_PATH: String = "user://language_resources/"
const MODEL_DATABASE_PATH: String = "res://model_database.db"
## The CSV lists packs used to carry beside language.db, which a Save deletes
## from the local copy (see _write_generated_files()).
const OBSOLETE_LISTS: PackedStringArray = ["gp_list.csv", "words_list.csv", "syllables_list.csv", "sentences_list.csv"]

var save_file: ProfToolSave
# The integrity check's own state. It lives down in its region, but its
# declarations belong here with the rest.
var integrity_checking: bool = false
var integrity_log_path: String = "user://database-integrity-log.txt"
var total_integrity_warnings: int = 0

@onready var language_select_button: OptionButton = %LanguageSelectButton
@onready var new_language_container: PanelContainer = %NewLanguageContainer
@onready var line_edit: LineEdit = %LineEdit
@onready var file_dialog: FileDialog = $FileDialog
@onready var file_dialog_export: FileDialog = $FileDialogExport
@onready var add_word_list_button: Button = $VBoxContainer/AddWordListButton
@onready var error_label: Label = %ErrorLabel
@onready var version_label: Label = %VersionLabel
@onready var tab_container: TabContainer = $CenterContainer/TabContainer
@onready var check_box_log: CheckBox = $CheckIntegrityButton/CheckBoxLog


func _ready() -> void:
	_silence_game_music()
	# Read from project.godot, the version the release bumps, so it cannot drift.
	version_label.text = "Version %s" % str(ProjectSettings.get_setting("application/config/version", ""))
	WordImporter.ensure_loaded()
	_update_add_word_list_button()
	save_file = ProfToolSave.load_or_create()
	_display_available_languages()
	# Clamped: the tab is read from a file, and a tab that no longer exists would
	# make the container error rather than open on the first one.
	tab_container.current_tab = clampi(save_file.main_menu_selected_tab, 0, tab_container.get_tab_count() - 1)
	tab_container.tab_changed.connect(_on_tab_container_tab_changed)


## Stops the game's title track, which its MusicManager autoload starts by
## itself after the first frame unless something has asked for music first.
## Looked up by path rather than by name, so the Prof Tool still compiles in a
## project that has no MusicManager -- where there is nothing to stop.
func _silence_game_music() -> void:
	var music_manager: Node = get_node_or_null(^"/root/MusicManager")
	if music_manager:
		music_manager.call(&"stop")


func _display_available_languages() -> void:
	for item: int in range(language_select_button.item_count - 1, 0, -1):
		language_select_button.remove_item(item)
	var available_languages: Array[String] = _get_available_languages()
	var ind: int = 1
	for available_language: String in available_languages:
		language_select_button.add_item(available_language)
		if available_language == save_file.selected_language:
			_open_language(save_file.selected_language)
			language_select_button.select(ind)
		ind += 1


func _update_add_word_list_button() -> void:
	if FileAccess.file_exists(WordImporter.word_list_path()):
		add_word_list_button.text = "Change Word List"
	else:
		add_word_list_button.text = "Add Word List"


func _on_gp_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/gp_list.tscn")


func _on_word_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/word_list.tscn")


func _on_syllable_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/syllable_list.tscn")


func _on_sentence_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/sentence_list.tscn")


func _on_lesson_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/lessons_list.tscn")


func _on_tracing_builder_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/tracing_builder.tscn")


func _on_data_loader_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/gp_image_and_sound_descriptions.tscn")


func _on_data_loader_button_2_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/gp_video_descriptions.tscn")


func _on_game_sounds_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/in_game_sounds.tscn")


func _on_pseudowords_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/boss_word_list.tscn")


func _on_speeches_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/kalulu_speeches.tscn")


func _on_exercises_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/lesson_exercises.tscn")


func _on_booklets_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/booklets.tscn")


## Saves the open pack as a folder: the language.db picked is where the pack's
## database goes, and its media and generated files go beside it -- the layout
## of a Kalulu-Languages pack, so saving onto Kalulu-Languages/fr_FR/language.db
## updates that pack in place. Nothing is zipped.
func _on_save_path_selected(file_path: String) -> void:
	if file_path.get_file() != PackFolder.DATABASE_FILE_NAME:
		error_label.text = "Save the pack as %s, not %s." % [PackFolder.DATABASE_FILE_NAME, file_path.get_file()]
		return
	var refusals: PackedStringArray = _pack_refusals()
	if not refusals.is_empty():
		error_label.text = "Not saved, Kalulu-Languages would refuse it: " + "; ".join(refusals)
		return
	_write_generated_files()
	var destination: String = file_path.get_base_dir()
	# Closed for the copy, so the language.db that leaves is complete; Windows
	# also refuses to read a file another handle holds open for writing.
	Database.close()
	var error: Error = PackFolder.copy(BASE_PATH.path_join(Database.language), destination)
	_open_language(Database.language)
	if error != OK:
		error_label.text = "%s could not be saved to %s (%s)." % [Database.language, destination, error_string(error)]
		return
	save_file.pack_folders[Database.language] = destination
	save_file.save()
	error_label.text = "%s saved to %s." % [Database.language, destination]


## What the Kalulu-Languages validator would reject in the booklet data, which
## other screens can leave behind (a lesson moved, a word ticked booklet-only):
## booklets not numbered 1, 2, 3... along the chapters (rule 8), a game sentence
## holding a booklet-only word (rule 7).
func _pack_refusals() -> PackedStringArray:
	var data: BookletData = BookletData.new()
	data.load_from_database()
	var refusals: PackedStringArray = data.save_errors()
	Database.db.query("SELECT COUNT(DISTINCT Sentences.ID) AS Count FROM Sentences
		INNER JOIN WordsInSentences ON WordsInSentences.SentenceID = Sentences.ID
		INNER JOIN Words ON Words.ID = WordsInSentences.WordID
		WHERE Sentences.BookletOnly = 0 AND Words.BookletOnly = 1")
	var count: int = int(Database.db.query_result[0].Count) if not Database.db.query_result.is_empty() else 0
	if count > 0:
		refusals.append("%d game sentence(s) hold a booklet-only word: save the Sentence List to mark them" % count)
	return refusals


## The files a saved pack carries besides its database and media: version.txt
## and summary.txt, written into the local copy of the pack. The CSV lists it
## used to carry are deleted from that copy, so the Save does not copy them back
## into a pack: nothing read them, and language.db holds the same data.
func _write_generated_files() -> void:
	_normalize_lesson_ids_before_export()

	var version_file: FileAccess = FileAccess.open(BASE_PATH.path_join(Database.language).path_join("version.txt"), FileAccess.WRITE)
	version_file.store_line(Time.get_datetime_string_from_system(true, false))
	version_file.close()
	
	var summary_file: FileAccess = FileAccess.open(BASE_PATH.path_join(Database.language).path_join("summary.txt"), FileAccess.WRITE)
	var sentences_by_lesson: Dictionary = Database.get_sentences_by_lessons()
	for index: int in range(Database.get_lessons_count()):
		
		var lesson: int = index +1
		
		summary_file.store_line("Lesson %s --------------------" % lesson)
		summary_file.store_line("\t \t Words ---")
		var words: String = ""
		for element: Dictionary in Database.get_words_for_lesson(lesson, true):
			words += element.Word + ", "
		summary_file.store_line(words.trim_suffix(", "))
		summary_file.store_line("\n")
		summary_file.store_line("\t \t Syllables ---")
		var syllables: String = ""
		for element: Dictionary in Database.get_syllables_for_lesson(lesson, true):
			syllables += element.Grapheme + ", "
		summary_file.store_line(syllables.trim_suffix(", "))
		summary_file.store_line("\n")
		summary_file.store_line("\t \t Sentences ---")
		for element: Dictionary in Database.get_sentences(lesson, true, sentences_by_lesson):
			summary_file.store_line(element.Sentence as String)
		summary_file.store_line("\n\n")
	summary_file.close()
	
	for file_name: String in OBSOLETE_LISTS:
		var path: String = BASE_PATH.path_join(Database.language).path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# Forces lessons to have a lessonID corresponding to the lesson number, to avoid confusion in game requests
func _normalize_lesson_ids_before_export() -> void:
	Database.db.query("SELECT ID, LessonNb FROM Lessons")
	var lessons: Array[Dictionary] = Database.db.query_result
	var remapped_lessons: Array[Dictionary] = []
	for lesson: Dictionary in lessons:
		var lesson_id: int = lesson.ID as int
		var lesson_nb: int = lesson.LessonNb as int
		if lesson_id != lesson_nb:
			remapped_lessons.push_back({"from": lesson_id, "to": lesson_nb, "temp": -1000000 - lesson_nb})

	if remapped_lessons.is_empty():
		return

	Database.db.query("PRAGMA foreign_keys = OFF")
	Database.db.query("BEGIN TRANSACTION")

	for table_name: String in _get_tables_with_lesson_id_column():
		for remap_lesson: Dictionary in remapped_lessons:
			Database.db.query_with_bindings("UPDATE %s SET LessonID = ? WHERE LessonID = ?" % table_name, [remap_lesson.to, remap_lesson.from])

	for remap_lesson: Dictionary in remapped_lessons:
		Database.db.query_with_bindings("UPDATE Lessons SET ID = ? WHERE ID = ?", [remap_lesson.temp, remap_lesson.from])

	for remap_lesson: Dictionary in remapped_lessons:
		Database.db.query_with_bindings("UPDATE Lessons SET ID = ? WHERE ID = ?", [remap_lesson.to, remap_lesson.temp])

	Database.db.query("COMMIT")
	Database.db.query("PRAGMA foreign_keys = ON")
	Log.trace("ProfToolMenu: Normalized %d mismatched lesson IDs before export" % remapped_lessons.size())


func _get_tables_with_lesson_id_column() -> Array[String]:
	Database.db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
	var tables: Array[Dictionary] = Database.db.query_result
	var tables_with_lesson_id_column: Array[String] = []
	for table_data: Dictionary in tables:
		var table_name: String = table_data.name as String
		if table_name == "Lessons":
			continue
		Database.db.query("PRAGMA table_info(%s)" % table_name)
		for table_column: Dictionary in Database.db.query_result:
			if (table_column.name as String) == "LessonID":
				tables_with_lesson_id_column.push_back(table_name)
				break
	return tables_with_lesson_id_column

#region Database integrity check

func _check_db_integrity() -> void:
	if integrity_checking:
		return
	integrity_checking = true
	error_label.text = "Database integrity check started."
	total_integrity_warnings = 0
	await get_tree().process_frame
	if check_box_log.button_pressed:
		if FileAccess.file_exists(integrity_log_path):
			DirAccess.remove_absolute(integrity_log_path)
	
	# The checks below see the game's entries only: the game leaves booklet-only
	# ones out. A game sentence holding a booklet-only word is said so here,
	# rather than as a word "not introduced yet" (Kalulu-Languages SCHEMA.md rule 7).
	Database.db.query("SELECT DISTINCT Sentences.Sentence AS Sentence, Words.Word AS Word FROM Sentences
		INNER JOIN WordsInSentences ON WordsInSentences.SentenceID = Sentences.ID
		INNER JOIN Words ON Words.ID = WordsInSentences.WordID
		WHERE Sentences.BookletOnly = 0 AND Words.BookletOnly = 1")
	for row: Dictionary in Database.db.query_result.duplicate():
		if !log_message("Sentence \"%s\" is offered by the game but holds the booklet-only word \"%s\": mark it booklet-only" % [row.Sentence, row.Word]):
			return

	var sentences_list: Dictionary = Database.get_sentences_by_lessons()
	if sentences_list.is_empty():
		if !log_message("No sentence found in database"):
					return
	var lesson_id: int
	var known_words_list: Dictionary = {}
	var known_gps_list: Array[Dictionary] = []
	var gp_known: bool = false
	for index: int in range(Database.get_lessons_count()):
		lesson_id = index +1
		error_label.text = "Database integrity checks lesson " + str(lesson_id)
		await get_tree().process_frame
		Log.trace("ProfToolMenu: Lesson_id = " + str(lesson_id))
		
		var new_gps_for_lesson: Array = Database.get_gps_for_lesson(lesson_id, false, true, false, false, true)
		for new_gp: Dictionary in new_gps_for_lesson:
			if !new_gp.has("ID"):
				if !log_message("GP with no ID in lesson " + str(lesson_id)):
					return
			if !new_gp.has("Grapheme"):
				if !log_message("GP (ID " + str(new_gp.ID) + ") with no Grapheme in lesson " + str(lesson_id)):
					return
			if !new_gp.has("Phoneme"):
				if !log_message("GP (ID " + str(new_gp.ID) + ") with no Phoneme in lesson " + str(lesson_id)):
					return
			var exists: bool = known_gps_list.any(func(d: Dictionary) -> bool: return d == new_gp)
			if exists:
				if !log_message("GP ID " + str(new_gp.ID) + " already exists in lesson " + str(lesson_id)):
					return
			else:
				known_gps_list.push_back(new_gp)
		
		var new_words_for_lesson: Array = Database.get_words_for_lesson(lesson_id, true, 1, 99, true)
		for new_word: Dictionary in new_words_for_lesson:
			if !new_word.has("ID"):
				if !log_message("Word with no ID in lesson ID " + str(lesson_id)):
					return
			if !new_word.has("GPs"):
				if !log_message("Word with no GPs (key) at lesson ID " + str(lesson_id) + " and word ID " + str(new_word.ID)):
					return
			if !new_word.has("Word"):
				if !log_message("Word with no Word (key) at lesson ID " + str(lesson_id) + " and word ID " + str(new_word.ID)):
					return
			for gp: Dictionary in new_word.GPs:
				if !gp.has("ID"):
					if !log_message("GP with no ID (key) at lesson ID " + str(lesson_id) + " in word " + (new_word.Word as String) + " (ID " + str(new_word.ID) + ")"):
						return
				gp_known = false
				for known_gp: Dictionary in known_gps_list:
					if known_gp.ID == gp.ID:
						gp_known = true
						break
				if !gp_known:
					if !log_message("Word " + (new_word.Word as String) + " with unknown GP (ID " + str(gp.ID) + ") at lesson ID " + str(lesson_id) + " and word ID " + str(new_word.ID)):
						return
			if known_words_list.has(new_word.Word):
				if !log_message('Word "' + (new_word.Word as String) + '" is introduced in lesson ID ' + str(lesson_id) + " but it already was introduced in lesson ID " + str(known_words_list[new_word.Word])):
					return
			known_words_list[new_word.Word] = lesson_id
		
		if sentences_list.has(lesson_id):
			for sentence: Dictionary in sentences_list[lesson_id]:
				if !sentence.has("ID"):
					if !log_message("Sentence with no ID in lesson ID " + str(lesson_id)):
						return
				if !sentence.has("Sentence"):
					if !log_message("Sentence with no Sentence (key) at lesson ID " + str(lesson_id) + " and sentence ID " + str(sentence.ID)):
						return
				# More robust word count from sentence text
				var text: String = (sentence.Sentence as String)
				text = text.replace("’", "'")
				text = text.replace("!", " ").replace("?", " ").replace(".", " ").replace(",", " ").replace(";", " ").replace(":", " ")
				text = text.replace("'", " ")
				while text.find("  ") != -1:
					text = text.replace("  ", " ")
				var word_count: int = text.strip_edges().split(" ", false).size()

				var word_list: Array[Dictionary] = _get_words_in_sentence_for_integrity_check(sentence.ID as int)

				# Existing check: mismatch between text word count and WordsInSentences entries
				if word_list.size() != word_count:
					if !log_message('Sentence "' + (sentence.Sentence as String) + '" (ID ' + str(sentence.ID) + ') has incoherent words count: expected ' + str(word_count) + ', got ' + str(word_list.size())):
						return

				# New check: detect missing WordPosition (holes) in WordsInSentences
				var positions_present: Dictionary = {} # int -> true
				var min_pos: int = 999999
				var max_pos: int = -999999
				var can_check_positions: bool = true

				for word_pos_entry: Dictionary in word_list:
					if word_pos_entry.has("WordPosition"):
						var position_index: int = word_pos_entry.WordPosition as int
						positions_present[position_index] = true
						min_pos = mini(min_pos, position_index)
						max_pos = maxi(max_pos, position_index)
					else:
						# If get_words_in_sentence does not return WordPosition, we cannot validate continuity.
						can_check_positions = false
						if !log_message('Sentence "' + (sentence.Sentence as String) + '" (ID ' + str(sentence.ID) + ') word_list entries have no WordPosition key; cannot check missing words by position.'):
							return
						break

				if can_check_positions and word_count > 0:
					# Expected positions are 0..(word_count-1)
					if !positions_present.has(0):
						if !log_message('Sentence "' + (sentence.Sentence as String) + '" (ID ' + str(sentence.ID) + ') has missing first word: WordPosition 0 absent. Present positions: ' + str(positions_present.keys())):
							return

					var expected_last: int = word_count - 1
					if !positions_present.has(expected_last):
						if !log_message('Sentence "' + (sentence.Sentence as String) + '" (ID ' + str(sentence.ID) + ') has missing last word: expected WordPosition ' + str(expected_last) + ' absent. Present positions: ' + str(positions_present.keys())):
							return

					for expected_pos: int in range(word_count):
						if !positions_present.has(expected_pos):
							if !log_message('Sentence "' + (sentence.Sentence as String) + '" (ID ' + str(sentence.ID) + ') is missing WordPosition ' + str(expected_pos) + ' in WordsInSentences. Present positions: ' + str(positions_present.keys())):
								return
				# Continue existing per-word checks
				for word: Dictionary in word_list:
					if !word.has("ID"):
						if !log_message("Word with no ID in lesson ID " + str(lesson_id) + " and sentence ID " + str(sentence.ID)):
							return
					if !word.has("Word"):
						if !log_message("Word with no Word (key) at lesson ID " + str(lesson_id) + ", sentence ID " + str(sentence.ID) + " and word ID " + str(word.ID)):
							return
					if !known_words_list.has(word.Word):
						if !log_message('Word "' + (word.Word as String) + '" is used in lesson ID ' + str(lesson_id) + ", sentence ID " + str(sentence.ID) + ", but it has not been introduced yet."):
							return
		else:
			continue #No sentence in this lesson
	
	error_label.text = "Database integrity checks all GP sounds file names."
	var all_gps: Array = Database.get_gps_for_lesson(Database.get_lessons_count() + 1, false, false, false, true, true)
	for gp: Dictionary in all_gps:
		var gp_sound_path: String = Database.get_gp_sound_path(gp)
		var result: Dictionary = file_exists_case_sensitive(gp_sound_path)
		match result.status:
			FileCheckResult.OK:
				pass # Nothing
			FileCheckResult.ERROR_CASE_MISMATCH:
				if !log_message("GP " + Database.get_gp_name(gp) + " sound file exists, but its name does not match the expected casing"):
					return
			FileCheckResult.ERROR_NOT_FOUND:
				# A pack that predates the file name encoding still plays, but it
				# should be told apart from a recording that is really missing.
				var found_files: PackedStringArray = Database.find_gp_asset_files(
						gp, Database.LANGUAGE_SOUNDS, Database.SOUND_EXTENSION)
				if not found_files.is_empty():
					if !log_message("GP " + Database.get_gp_name(gp) + " sound file is only found as " + found_files[0].get_file() + ", expected " + gp_sound_path.get_file()):
						return
				elif !log_message("GP " + Database.get_gp_name(gp) + " sound file does not exists"):
					return
	
	error_label.text = "Database integrity check finished. " + str(total_integrity_warnings) + " warnings found."
	integrity_checking = false
	if check_box_log.button_pressed:
		var file_path: String = ProjectSettings.globalize_path(integrity_log_path)
		Log.trace("ProfToolMenu: Logs saved at " + file_path)
		OS.shell_open(file_path)


func _get_words_in_sentence_for_integrity_check(sentence_id: int) -> Array[Dictionary]:
	Database.db.query_with_bindings(
		"SELECT
			Words.ID AS ID,
			Words.Word AS Word,
			WordsInSentences.Position AS WordPosition,
			WordsInSentences.SentenceID AS SentenceID
		FROM WordsInSentences
		INNER JOIN Words ON Words.ID = WordsInSentences.WordID
		WHERE WordsInSentences.SentenceID = ?
		ORDER BY WordsInSentences.Position ASC",
		[sentence_id]
	)
	return Database.db.query_result

#endregion

func log_message(message: String) -> bool:
	total_integrity_warnings += 1
	if check_box_log.button_pressed:
		var file: FileAccess
		if FileAccess.file_exists(integrity_log_path):
			file = FileAccess.open(integrity_log_path, FileAccess.READ_WRITE)
			file.seek_end() # Move to the end to append
		else:
			file = FileAccess.open(integrity_log_path, FileAccess.WRITE_READ)
		if file:
			file.seek_end()
			file.store_line(message)
			file.close()
		else:
			Log.warn("ProfToolMenu: Integrity log file not found")
		return true
	else:
		error_label.text = message
		integrity_checking = false
		return false


func file_exists_case_sensitive(path: String) -> Dictionary:
	var result: Dictionary = {
		"status": FileCheckResult.OK,
		"exists": false
	}

	if not FileAccess.file_exists(path):
		result.status = FileCheckResult.ERROR_NOT_FOUND
		return result

	var dir_path: String = path.get_base_dir()
	var file_name: String = path.get_file()

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		result.status = FileCheckResult.ERROR_NOT_FOUND
		return result

	dir.list_dir_begin()
	while true:
		var test_name: String = dir.get_next()
		if test_name == "":
			break
		if !dir.current_is_dir():
			if test_name == file_name:
				result.exists = true
				result.status = FileCheckResult.OK
				dir.list_dir_end()
				return result
			elif test_name.to_lower() == file_name.to_lower():
				result.status = FileCheckResult.ERROR_CASE_MISMATCH
	dir.list_dir_end()

	if result.status != FileCheckResult.ERROR_CASE_MISMATCH:
		result.status = FileCheckResult.ERROR_NOT_FOUND

	return result


func _get_available_languages() -> Array[String]:
	var available_languages: Array[String] = []
	var dir: DirAccess = DirAccess.open(BASE_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if FileAccess.file_exists(BASE_PATH.path_join(file_name).path_join("language.db")):
					available_languages.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return available_languages


func _on_language_select_button_item_selected(index: int) -> void:
	if index == 0:
		new_language_container.show()
		line_edit.grab_focus()
		return
	else:
		new_language_container.hide()
	
	save_file.selected_language = language_select_button.get_item_text(index)
	save_file.save()
	_open_language(save_file.selected_language)


## Opens a pack and brings its database to the schema this Prof Tool writes
## (PackSchema). A pack it cannot bring there -- one made by a newer Prof Tool,
## usually -- is closed again and nothing that reads or writes it can be pressed,
## so no screen or export runs against a schema it does not know.
func _open_language(language: String) -> void:
	Database.language = language
	var error: String = PackSchema.upgrade(Database.db) if Database.is_open else "The database of %s could not be opened." % language
	if not error.is_empty():
		Log.error("ProfToolMenu: %s: %s" % [language, error])
		error_label.text = error
		Database.close()
	else:
		# Database looked for the flag when it opened the pack, which may have been
		# before the upgrade added it.
		Database.detect_booklet_only()
	_set_pack_controls_disabled(not error.is_empty())


func _set_pack_controls_disabled(disabled: bool) -> void:
	var controls: Array[Node] = [$ExportButton, $CheckIntegrityButton]
	for tab: Node in tab_container.get_children():
		controls.append_array(tab.get_children())
	for control: Node in controls:
		if control is BaseButton:
			(control as BaseButton).disabled = disabled


func _on_validate_language_pressed() -> void:
	if not line_edit.text:
		return
		
	# The model is a .db, not a Godot resource, so an export only carries it when
	# the preset's include_filter names it. Opened before the folder is made, so a
	# build without it leaves no empty language behind.
	var file: FileAccess = FileAccess.open(MODEL_DATABASE_PATH, FileAccess.READ)
	if file == null:
		var msg: String = "Cannot create a language: %s is missing from this build (%s)" % [MODEL_DATABASE_PATH, error_string(FileAccess.get_open_error())]
		Log.error("ProfToolMenu: " + msg)
		error_label.text = msg
		return
	DirAccess.make_dir_recursive_absolute(BASE_PATH.path_join(line_edit.text))
	var dest_path: String = BASE_PATH.path_join(line_edit.text).path_join("language.db")
	var dest: FileAccess = FileAccess.open(dest_path, FileAccess.WRITE)
	if dest == null:
		var msg: String = "Cannot create a language: %s cannot be written (%s)" % [dest_path, error_string(FileAccess.get_open_error())]
		Log.error("ProfToolMenu: " + msg)
		error_label.text = msg
		file.close()
		return
	dest.store_buffer(file.get_buffer(file.get_length()))
	file.close()
	dest.close()
	save_file.selected_language = line_edit.text
	save_file.save()
	get_tree().reload_current_scene()


func _word_list_file_selected(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.copy_absolute(file_path, WordImporter.word_list_path())
		var msg: String = WordImporter.load_word_list()
		error_label.text = msg
		# Check that the words we have in database have the correct gpmatch, if not update them
		var query: String = "SELECT Words.ID as WordId, Word, group_concat(Grapheme, ' ') as Graphemes, group_concat(Phoneme, ' ') as Phonemes, group_concat(GPs.ID, ' ') as GPIDs, Words.Exception 
				FROM Words 
				INNER JOIN ( SELECT * FROM GPsInWords ORDER BY GPsInWords.Position ) GPsInWords ON Words.ID = GPsInWords.WordID 
				INNER JOIN GPs ON GPs.ID = GPsInWords.GPID
				GROUP BY Words.ID"
		Database.db.query(query)
		var results: Array[Dictionary] = Database.db.query_result
		var word_list_element: WordListElement = (load("res://sources/language_tool/word_list_element.tscn") as PackedScene).instantiate()
		for result: Dictionary in results:
			var same: bool = true
			var master_gpmatch: String = WordImporter.word_list[result.Word].GPMATCH
			var master_gplist: PackedStringArray = master_gpmatch.trim_prefix("(").trim_suffix(")").split(".")
			var graphemes: PackedStringArray = (result.Graphemes as String).split(" ")
			var phonemes: PackedStringArray = (result.Phonemes as String).split(" ")
			if master_gplist.size() != graphemes.size():
				same = false
			else:
				for index: int in range(master_gplist.size()):
					same = same and (graphemes[index] + "-" + phonemes[index] == master_gplist[index])
			if not same:
				Database.db.delete_rows("Words", "ID=%s" % result.WordId)
				word_list_element._add_from_additional_word_list(result.Word as String)


func _on_add_word_list_button_pressed() -> void:
	file_dialog.filters = []
	file_dialog.add_filter("*.csv", "csv")
	ProfToolUtils.disconnect_all(file_dialog.file_selected)
	file_dialog.file_selected.connect(_word_list_file_selected)
	file_dialog.show()
	_update_add_word_list_button()


func _on_import_language_button_pressed() -> void:
	file_dialog.title = "Open a language pack's %s" % PackFolder.DATABASE_FILE_NAME
	file_dialog.filters = []
	file_dialog.add_filter(PackFolder.DATABASE_FILE_NAME, "Language pack database")
	_start_in_pack_folder(file_dialog, save_file.selected_language)
	ProfToolUtils.disconnect_all(file_dialog.file_selected)
	file_dialog.file_selected.connect(_on_language_database_selected)
	file_dialog.show()


func _on_export_button_pressed() -> void:
	file_dialog_export.title = "Save %s as a %s, beside its media" % [Database.language, PackFolder.DATABASE_FILE_NAME]
	file_dialog_export.filters = []
	# A pattern, not the file name: in save mode the dialog matches the filter
	# against the whole path, and on a miss appends the filter minus its first
	# character -- a "language.db" filter saved language.db as
	# language.dbanguage.db. _on_save_path_selected checks the name itself.
	file_dialog_export.add_filter("*.db", "Language pack database")
	_start_in_pack_folder(file_dialog_export, Database.language)
	file_dialog_export.current_file = PackFolder.DATABASE_FILE_NAME
	ProfToolUtils.disconnect_all(file_dialog_export.file_selected)
	file_dialog_export.file_selected.connect(_on_save_path_selected)
	file_dialog_export.show()


## Points a dialog at the folder the language's pack was last opened from or
## saved to, when there is one and it still exists. Otherwise the dialog stays
## where it was.
func _start_in_pack_folder(dialog: FileDialog, language: String) -> void:
	var folder: String = save_file.pack_folders.get(language, "")
	if not folder.is_empty() and DirAccess.dir_exists_absolute(folder):
		dialog.current_dir = folder


## Opens a pack from its language.db. The folder holding it is the pack, and its
## name is the language's: it is copied into BASE_PATH under that name, and the
## copy is what every screen edits until the pack is saved back out.
func _on_language_database_selected(file_path: String) -> void:
	if file_path.get_file() != PackFolder.DATABASE_FILE_NAME:
		error_label.text = "A language pack's database is called %s, not %s." % [PackFolder.DATABASE_FILE_NAME, file_path.get_file()]
		return
	var source: String = file_path.get_base_dir()
	var language: String = source.get_file()
	if language.is_empty():
		error_label.text = "%s must be inside the pack's own folder, which names the language." % PackFolder.DATABASE_FILE_NAME
		return
	# The local copy is about to be overwritten, and Windows refuses to replace
	# a database that is still open.
	var replacing_open_pack: bool = language == Database.language
	if replacing_open_pack:
		Database.close()
	# Mirrored, not copied over: a file the pack has since dropped would stay in
	# the local copy, and Save would put it back into the pack.
	var error: Error = PackFolder.mirror(source, BASE_PATH.path_join(language))
	if error != OK:
		if replacing_open_pack:
			_open_language(language)
		error_label.text = "%s could not be opened (%s)." % [file_path, error_string(error)]
		return
	save_file.selected_language = language
	save_file.pack_folders[language] = source
	save_file.save()
	get_tree().reload_current_scene()


func _on_open_folder_button_pressed() -> void:
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(BASE_PATH))


func _on_tab_container_tab_changed(tab: int) -> void:
	save_file.main_menu_selected_tab = tab
	save_file.save()
