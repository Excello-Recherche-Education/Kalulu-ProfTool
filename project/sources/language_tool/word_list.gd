class_name WordList
extends Control

@export var element_scene: PackedScene = preload("res://sources/language_tool/word_list_element.tscn")

var undo_redo: UndoRedo = UndoRedo.new()
var in_new_gp_mode: bool = false:
	set = set_in_new_gp_mode
var _element: WordListElement
var sub_elements_list: Dictionary = {}
var new_gp_asked_element: WordListElement
var new_gp_asked_ind: int

@onready var elements_container: VBoxContainer = %ElementsContainer
@onready var new_gp_layer: CanvasLayer = $NewGPLayer
@onready var new_gp: Variant = %NewGP
@onready var title: ListTitle = %ListTitle
@onready var lesson_title: Label = %Lesson
@onready var word_title: Label = %Word
@onready var graphemes_title: Label = %Graphemes
@onready var error_label: Label = %ErrorLabel


func create_sub_elements_list() -> void:
	sub_elements_list.clear()
	Database.db.query("Select * FROM GPs ORDER BY GPs.Grapheme")
	for element: Dictionary in Database.db.query_result:
		sub_elements_list[element.ID] = {
			grapheme = element.Grapheme,
			phoneme = element.Phoneme,
		}


func _ready() -> void:
	create_sub_elements_list()
	
	_element = element_scene.instantiate()
	
	Database.db.query(_get_query())
	
	var results: Array[Dictionary] = Database.db.query_result
	for elem: Dictionary in results:
		var element: WordListElement = element_scene.instantiate()
		element.sub_elements_list = sub_elements_list
		element.word = elem[_element.table_graph_column]
		element.id = elem[_element.table_graph_column + "Id"]
		element.exception = elem.Exception
		element.reading = elem.Reading
		element.writing = elem.Writing
		element.booklet_only = elem.BookletOnly
		element.set_gp_ids_from_string(elem[_element.sub_table_id + "s"] as String)
		elements_container.add_child(element)
		element.undo_redo = undo_redo
		element.delete_pressed.connect(_on_element_delete_pressed.bind(element))
		element.new_gp_asked.connect(_on_element_new_gp_asked.bind(element))
		element.gps_updated.connect(_on_gps_updated)
		element.update_lesson()
	
	_show_no_decomposition_count()
	title.set_title(_element.table_graph_column + " List")
	lesson_title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	word_title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	word_title.text = _element.table_graph_column
	graphemes_title.text = _element.sub_table
	_reorder_by("lesson")


# The INNER JOIN query lists every entry that has a decomposition, its parts in
# Position order; the second SELECT adds the entries that have none, with empty
# strings for their parts, which the INNER JOIN matched nowhere and so could be
# neither seen, decomposed nor deleted here. Do not turn the first one into a LEFT
# JOIN instead: SQLite then plans it differently and group_concat stops following
# Position, so Save, which compares that string with the list's, deletes the entry.
func _get_query() -> String:
	return "SELECT %s.ID as %sId, %s, group_concat(%s, ' ') as %ss, group_concat(%s, ' ') as %ss, group_concat(%s.ID, ' ') as %ss, %s.Exception, %s.Reading, %s.Writing, %s.BookletOnly 
			FROM %s 
			INNER JOIN ( SELECT * FROM %s ORDER BY %s.Position ) %s ON %s.ID = %s.%sID 
			INNER JOIN %s ON %s.ID = %s.%s
			GROUP BY %s.ID
			UNION ALL
			SELECT ID, %s, '', '', '', Exception, Reading, Writing, BookletOnly
			FROM %s
			WHERE ID NOT IN ( SELECT %sID FROM %s )" % [_element.table, _element.table_graph_column,
				_element.table_graph_column, _element.sub_table_graph_column, _element.sub_table_graph_column,
				_element.sub_table_phon_column, _element.sub_table_phon_column,
				_element.sub_table, _element.sub_table_id, _element.table, _element.table, _element.table, _element.table,
				_element.table,
				_element.relational_table, _element.relational_table, _element.relational_table, _element.table, _element.relational_table, _element.table_graph_column,
				_element.sub_table, _element.sub_table, _element.relational_table, _element.sub_table_id,
				_element.table,
				_element.table_graph_column, _element.table,
				_element.table_graph_column, _element.relational_table]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_undo"):
		undo_redo.undo()
	elif event.is_action_pressed("ui_redo"):
		undo_redo.redo()


func _on_element_delete_pressed(element: Control) -> void:
	undo_redo.create_action("delete")
	undo_redo.add_do_method(elements_container.remove_child.bind(element))
	undo_redo.add_undo_method(elements_container.add_child.bind(element))
	undo_redo.add_undo_method(elements_container.move_child.bind(element, element.get_index()))
	undo_redo.commit_action()


func _on_plus_button_pressed() -> void:
	undo_redo.create_action("add")
	var element: WordListElement = element_scene.instantiate()
	element.sub_elements_list = sub_elements_list
	element.word = ""
	element.undo_redo = undo_redo
	element.delete_pressed.connect(_on_element_delete_pressed.bind(element))
	element.new_gp_asked.connect(_on_element_new_gp_asked.bind(element))
	element.gps_updated.connect(_on_gps_updated)
	undo_redo.add_do_method(elements_container.add_child.bind(element))
	undo_redo.add_do_method(elements_container.move_child.bind(element, 0))
	undo_redo.add_undo_method(elements_container.remove_child.bind(element))
	undo_redo.commit_action()
	element.edit_mode()


func _on_element_new_gp_asked(ind: int, element: WordListElement) -> void:
	in_new_gp_mode = true
	new_gp_asked_element = element
	new_gp_asked_ind = ind
	if new_gp is WordListElement:
		(new_gp as WordListElement).edit_mode()
	elif new_gp is GPListElement:
		(new_gp as GPListElement).edit_mode()
	else:
		Log.error("WordList: Variable new_gp is of unknown type %s" % type_string(typeof(new_gp)))


func set_in_new_gp_mode(p_in_new_gp_mode: bool) -> void:
	in_new_gp_mode = p_in_new_gp_mode
	new_gp_layer.set_visible(in_new_gp_mode)


func _on_gp_list_element_validated() -> void:
	if new_gp is WordListElement:
		(new_gp as WordListElement).insert_in_database()
	elif new_gp is GPListElement:
		(new_gp as GPListElement).insert_in_database()
	else:
		Log.error("WordList: Variable new_gp is of unknown type %s" % type_string(typeof(new_gp)))
	if new_gp is Object:
		if (new_gp as Object).has_method("update_lesson"):
			if new_gp is WordListElement:
				(new_gp as WordListElement).update_lesson()
			elif new_gp is SentenceListElement:
				(new_gp as SentenceListElement).update_lesson()
			else:
				Log.error("WordList: Variable new_gp is of unknown type %s" % type_string(typeof(new_gp)))
	else:
		Log.error("WordList: Variable new_gp is of unknown type %s" % type_string(typeof(new_gp)))
	in_new_gp_mode = false
	create_sub_elements_list()
	for element: WordListElement in elements_container.get_children():
		element.sub_elements_list = sub_elements_list
	new_gp_asked_element.new_gp_asked_added(new_gp_asked_ind, new_gp.id as int)


func _on_gps_updated() -> void:
	create_sub_elements_list()
	for element: WordListElement in elements_container.get_children():
		element.sub_elements_list = sub_elements_list


func _on_save_button_pressed() -> void:
	for element: WordListElement in elements_container.get_children():
		element.insert_in_database()
	Database.db.query(_get_query())
	var result: Array[Dictionary] = Database.db.query_result
	for elem: Dictionary in result:
		var found: bool = false
		for element: WordListElement in elements_container.get_children():
			if " ".join(element.gp_ids) == elem[_element.sub_table_id + "s"] and element.word == elem[_element.table_graph_column]:
				found = true
				break
		if not found:
			Database.db.delete_rows(_element.table, "ID=%s" % elem[_element.table_graph_column + "Id"])
	undo_redo.clear_history()
	_mark_sentences_of_booklet_only_words()


## A game sentence holding a booklet-only word would bring that word back into
## the game (Kalulu-Languages SCHEMA.md rule 7), so ticking Booklet only on a
## word, or saving a sentence, makes every such sentence booklet-only too.
func _mark_sentences_of_booklet_only_words() -> void:
	var holding: String = "SELECT WordsInSentences.SentenceID FROM WordsInSentences
		INNER JOIN Words ON Words.ID = WordsInSentences.WordID
		WHERE Words.BookletOnly = 1"
	Database.db.query("SELECT ID FROM Sentences WHERE BookletOnly = 0 AND ID IN (%s)" % holding)
	var marked: Dictionary[int, bool] = {}
	for row: Dictionary in Database.db.query_result:
		marked[int(row.ID)] = true
	if marked.is_empty():
		return
	Database.db.query("UPDATE Sentences SET BookletOnly = 1 WHERE BookletOnly = 0 AND ID IN (%s)" % holding)
	# On the Sentence List, the rows on screen follow, or the next Save would
	# write 0 back before marking them again.
	if _element.table == "Sentences":
		for element: WordListElement in elements_container.get_children():
			if marked.has(element.id):
				element.booklet_only = 1
	error_label.text = "%d sentence(s) holding a booklet-only word are now booklet-only too." % marked.size()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://sources/language_tool/prof_tool_menu.tscn")


func _reorder_by(property_name: String) -> void:
	ProfToolUtils.reorder_children_by_property(elements_container, property_name)
	# Entries with no decomposition stay at the top whatever the sort, in the
	# order it gave them.
	var undecomposed: Array[WordListElement] = []
	for element: WordListElement in elements_container.get_children():
		if element.has_no_decomposition():
			undecomposed.append(element)
	for index: int in range(undecomposed.size()):
		elements_container.move_child(undecomposed[index], index)


func _show_no_decomposition_count() -> void:
	var count: int = 0
	for element: WordListElement in elements_container.get_children():
		if element.has_no_decomposition():
			count += 1
	if count > 0:
		var noun: String = _element.table_graph_column.to_lower()
		error_label.text = "⚠ %d %s(s) with no %s, at the top of the list: add them, or delete the %s(s)." % [count, noun, _element.sub_table, noun]


func _on_list_title_add_pressed() -> void:
	_on_plus_button_pressed()


func _on_list_title_back_pressed() -> void:
	_on_back_button_pressed()


func _on_list_title_new_search(new_text: String) -> void:
	for element: WordListElement in elements_container.get_children():
		element.set_visible(element.word.begins_with(new_text))


func _on_list_title_save_pressed() -> void:
	_on_save_button_pressed()


func _on_lesson_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		_reorder_by("lesson")


func _on_word_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		_reorder_by(_element.table_graph_column.to_lower())


func _on_list_title_import_path_selected(path: String, match_to_file: bool) -> void:
	if not FileAccess.file_exists(path):
		Log.error("WordList: File not found %s" % path)
		error_label.text = "File not found"
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var error: Error = FileAccess.get_open_error()
	if error != OK:
		Log.error("WordList: Cannot open file %s. Error: %s" % [path, error_string(error)])
		return
	if file == null:
		Log.error("WordList: Cannot open file %s. File is null" % path)
		return
	var line: PackedStringArray = file.get_csv_line()
	if line.size() < 2 or line[0] != "ORTHO" or line[1] != "GPMATCH":
		error_label.text = "Column names should be ORTHO, GPMATCH"
		return
	var all_data: Dictionary = {}
	while not file.eof_reached():
		line = file.get_csv_line()
		if line.size() < 2:
			continue
		_element._try_to_complete_from_word(line[0])
		all_data[line[0]] = true
	get_tree().reload_current_scene()
	
	# delete elements that are not in file
	if match_to_file:
		# Booklet-only entries are not the file's: a lexicon need not list them.
		var query: String = "Select * FROM Words WHERE BookletOnly = 0"
		Database.db.query(query)
		var result: Array[Dictionary] = Database.db.query_result
		for element: Dictionary in result:
			if not element.Word in all_data:
				Database.db.delete_rows("Words", "ID=%s" % element.ID)
		
