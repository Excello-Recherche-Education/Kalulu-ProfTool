extends Control
## The Booklets screen: what each chapter of the printed reading booklets
## contains (Kalulu-Languages SCHEMA.md, "The reading booklets").
##
## Chapters are listed on the left in the app's lesson order; the right side
## edits the one selected, or the language's settings. Nothing is written until
## Save, which writes everything in one transaction. The controls are built here
## rather than in the scene: the chapter editor is a long form whose rows depend
## on the chapter, which a scene could only describe once.

const MENU_SCENE: String = "res://sources/language_tool/prof_tool_menu.tscn"
const WARNING_COLOR: Color = Color(1.0, 0.6, 0.1)
const TEXT_SIZE: int = 36
const HEADING_SIZE: int = 48

var data: BookletData = BookletData.new()
var _chapter: BookletData.Chapter = null
## Chapter -> the sentences text being typed, kept while it names sentences the
## Sentence List does not have, so nothing typed is lost before they are added.
var _sentence_drafts: Dictionary[BookletData.Chapter, String] = {}
var _dirty: bool = false

var _chapter_list: ItemList
var _lesson_picker: OptionButton
var _editor: VBoxContainer
var _status: Label
var _problems_label: Label
var _add_missing_button: Button
var _problems_timer: Timer


func _ready() -> void:
	_build_layout()
	data.load_from_database()
	_fill_chapter_list()
	_show_settings()


#region Layout

func _build_layout() -> void:
	var background: Panel = Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	root.add_child(top)
	top.add_child(_button("Back", _on_back_pressed))
	var title: Label = Label.new()
	title.text = "Booklets"
	title.add_theme_font_size_override("font_size", 80)
	top.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", TEXT_SIZE)
	top.add_child(_status)
	top.add_child(_button("Save", _on_save_pressed))

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 760
	left.add_theme_constant_override("separation", 15)
	split.add_child(left)
	left.add_child(_button("Language settings", _show_settings))
	_chapter_list = ItemList.new()
	_chapter_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chapter_list.add_theme_font_size_override("font_size", TEXT_SIZE)
	_chapter_list.item_selected.connect(_on_chapter_selected)
	left.add_child(_chapter_list)
	var add_row: HBoxContainer = HBoxContainer.new()
	left.add_child(add_row)
	_lesson_picker = _option_button()
	for lesson_nb: int in data_lesson_numbers():
		_lesson_picker.add_item("Lesson %d" % lesson_nb, lesson_nb)
	add_row.add_child(_lesson_picker)
	add_row.add_child(_button("Add chapter", _on_add_chapter_pressed))
	var move_row: HBoxContainer = HBoxContainer.new()
	left.add_child(move_row)
	move_row.add_child(_button("Up", _on_move_pressed.bind(-1)))
	move_row.add_child(_button("Down", _on_move_pressed.bind(1)))
	move_row.add_child(_button("Delete chapter", _on_delete_chapter_pressed))

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_editor = VBoxContainer.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 12)
	scroll.add_child(_editor)

	_problems_timer = Timer.new()
	_problems_timer.one_shot = true
	_problems_timer.wait_time = 0.6
	_problems_timer.timeout.connect(_show_problems)
	add_child(_problems_timer)


# The lesson numbers of the pack, read before data is loaded.
func data_lesson_numbers() -> Array[int]:
	var numbers: Array[int] = []
	Database.db.query("SELECT LessonNb FROM Lessons ORDER BY LessonNb")
	for row: Dictionary in Database.db.query_result:
		numbers.append(int(row.LessonNb))
	return numbers


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", TEXT_SIZE)
	button.pressed.connect(callback)
	return button


# Wrapped only where it has the editor's width to itself: a wrapped label in a
# row or a grid cell has no minimum width, and is squeezed to one letter a line.
func _label(text: String, size: int = TEXT_SIZE, wrapped: bool = true) -> Label:
	var label: Label = Label.new()
	label.text = text
	if wrapped:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


# An OptionButton sized by its row, not by its longest item, which would widen
# the whole editor past the screen.
func _option_button() -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.fit_to_longest_item = false
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", TEXT_SIZE)
	return option


func _heading(text: String) -> void:
	var label: Label = _label(text, HEADING_SIZE)
	_editor.add_child(HSeparator.new())
	_editor.add_child(label)


func _clear_editor() -> void:
	for child: Node in _editor.get_children():
		_editor.remove_child(child)
		child.queue_free()
	_problems_label = null
	_add_missing_button = null


func _spin_box(value: float, lowest: float, highest: float, real: bool, on_change: Callable) -> SpinBox:
	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = lowest
	spin_box.max_value = highest if highest >= 0 else 999
	spin_box.step = 0.05 if real else 1.0
	spin_box.value = value
	spin_box.custom_minimum_size.x = 260
	spin_box.get_line_edit().add_theme_font_size_override("font_size", TEXT_SIZE)
	spin_box.value_changed.connect(on_change)
	return spin_box


func _text_edit(text: String, height: float, on_change: Callable) -> TextEdit:
	var text_edit: TextEdit = TextEdit.new()
	text_edit.text = text
	text_edit.custom_minimum_size.y = height
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.add_theme_font_size_override("font_size", TEXT_SIZE)
	text_edit.text_changed.connect(func() -> void: on_change.call(text_edit.text))
	return text_edit


# A setting's editor: a choice list for the fonts, a number for the rest.
func _setting_control(column: String, value: float, on_change: Callable) -> Control:
	var spec: Array = BookletData.SETTINGS[column]
	if column == "SentenceFont" or column == "SentenceFirstFont":
		var names: PackedStringArray = BookletData.SENTENCE_FONTS if column == "SentenceFont" else BookletData.FIRST_FONTS
		var option: OptionButton = _option_button()
		option.custom_minimum_size.x = 360
		for index: int in range(names.size()):
			if not names[index].is_empty():
				option.add_item(names[index], index)
		option.select(option.get_item_index(int(value)))
		option.item_selected.connect(func(index: int) -> void: on_change.call(float(option.get_item_id(index))))
		return option
	return _spin_box(value, spec[1], spec[2], spec[3], on_change)


func _setting_text(column: String, value: float) -> String:
	if column == "SentenceFont":
		return BookletData.SENTENCE_FONTS[int(value)]
	if column == "SentenceFirstFont":
		return BookletData.FIRST_FONTS[int(value)]
	return str(value) if BookletData.SETTINGS[column][3] else str(int(value))

#endregion

#region Chapter list

func _fill_chapter_list() -> void:
	_chapter_list.clear()
	var booklet: int = 0
	for chapter: BookletData.Chapter in data.chapters:
		if chapter.booklet != booklet:
			booklet = chapter.booklet
			var separator: int = _chapter_list.add_item("— Booklet %d —" % booklet)
			_chapter_list.set_item_selectable(separator, false)
			_chapter_list.set_item_disabled(separator, true)
		var title: String = chapter.title.replace("\n", " / ")
		var index: int = _chapter_list.add_item("Lesson %d.%d   %s" % [chapter.lesson_nb, chapter.position + 1, title if not title.is_empty() else "(no title)"])
		_chapter_list.set_item_metadata(index, chapter)
		if chapter == _chapter:
			_chapter_list.select(index)


func _on_chapter_selected(index: int) -> void:
	var chapter: Variant = _chapter_list.get_item_metadata(index)
	if chapter is BookletData.Chapter:
		_show_chapter(chapter as BookletData.Chapter)


func _on_add_chapter_pressed() -> void:
	if _lesson_picker.selected < 0:
		return
	var lesson_nb: int = _lesson_picker.get_item_id(_lesson_picker.selected)
	var chapter: BookletData.Chapter = data.add_chapter(data.lesson_ids[lesson_nb])
	_changed()
	_chapter = chapter
	_fill_chapter_list()
	_show_chapter(chapter)


## Moves the selected chapter among the chapters of its lesson; chapters never
## leave their lesson's place in the order.
func _on_move_pressed(direction: int) -> void:
	if _chapter == null:
		return
	var target: int = _chapter.position + direction
	for other: BookletData.Chapter in data.chapters:
		if other.lesson_id == _chapter.lesson_id and other.position == target:
			other.position = _chapter.position
			_chapter.position = target
			data.sort_chapters()
			_changed()
			_fill_chapter_list()
			_show_chapter(_chapter)
			return


func _on_delete_chapter_pressed() -> void:
	if _chapter == null:
		return
	data.chapters.erase(_chapter)
	_sentence_drafts.erase(_chapter)
	data.sort_chapters()
	_chapter = null
	_changed()
	_fill_chapter_list()
	_show_settings()

#endregion

#region Editors

func _show_settings() -> void:
	_chapter = null
	_chapter_list.deselect_all()
	_clear_editor()
	_editor.add_child(_label("Language settings", 60))
	_editor.add_child(_label("Every chapter uses these unless it sets its own."))
	var cursive: CheckBox = CheckBox.new()
	cursive.text = "Written in cursive too (titles, sentences, writing pages). Unticked: everything in script, and the sentence fonts below are ignored"
	cursive.add_theme_font_size_override("font_size", TEXT_SIZE)
	cursive.button_pressed = data.settings.get("Cursive", 1.0) != 0.0
	cursive.toggled.connect(func(pressed: bool) -> void:
		data.settings["Cursive"] = float(pressed)
		_changed())
	_editor.add_child(cursive)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	_editor.add_child(grid)
	for column: String in BookletData.SETTINGS:
		grid.add_child(_label(BookletData.SETTINGS[column][0], TEXT_SIZE, false))
		grid.add_child(_setting_control(column, data.settings.get(column, 0.0), func(value: float) -> void:
			data.settings[column] = value
			_changed()))


func _show_chapter(chapter: BookletData.Chapter) -> void:
	_chapter = chapter
	_clear_editor()
	_editor.add_child(_label("Lesson %d, chapter %d" % [chapter.lesson_nb, chapter.position + 1], 60))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_editor.add_child(row)
	row.add_child(_label("Booklet", TEXT_SIZE, false))
	row.add_child(_spin_box(chapter.booklet, 1, 99, false, func(value: float) -> void:
		chapter.booklet = int(value)
		_changed()
		_fill_chapter_list()))
	var grey: CheckBox = CheckBox.new()
	grey.text = "Silent letters in grey"
	grey.add_theme_font_size_override("font_size", TEXT_SIZE)
	grey.button_pressed = chapter.grey_silent
	grey.toggled.connect(func(pressed: bool) -> void:
		chapter.grey_silent = pressed
		_changed())
	row.add_child(grey)

	_heading("Title")
	_editor.add_child(_label("Printed in script, and in cursive beside it when the language is. One line per line of the title; empty for no title."))
	var title_edit: TextEdit = _text_edit(chapter.title, 150, func(text: String) -> void:
		chapter.title = text.strip_edges()
		_changed()
		_fill_chapter_list())
	_editor.add_child(title_edit)
	_editor.add_child(_button("Title from the chapter's GPs", func() -> void:
		title_edit.text = data.title_for(chapter.gp_ids)
		title_edit.text_changed.emit()))

	_heading("What the chapter teaches")
	_editor.add_child(_label("Its automatic syllables and words contain at least one of these GPs."))
	_editor.add_child(_gp_checkboxes(chapter))
	_editor.add_child(_label("Teacher's booklet picture"))
	_editor.add_child(_image_picker(chapter))

	_heading("Own settings")
	_editor.add_child(_label("Ticked: this chapter's own value. Unticked: the language's."))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	_editor.add_child(grid)
	for column: String in BookletData.SETTINGS:
		_add_override_row(grid, chapter, column)

	_heading("Syllables")
	_editor.add_child(_label("One per line, repeated until the count is reached. Empty: chosen from the syllables the lesson can read."))
	_add_entries_editor(chapter, BookletData.Part.SYLLABLES, 150)
	_heading("Words")
	_editor.add_child(_label("One entry per line, as printed (\"la Lune\", \"un vélo\"). Empty: chosen from the words the lesson can read."))
	_add_entries_editor(chapter, BookletData.Part.WORDS, 260)
	_heading("Sentences")
	_editor.add_child(_label("Alternating: script and cursive take turns, paragraph by paragraph. One printed line per line, \" | \" between sentences on the same line, an empty line between paragraphs, %s for a line break inside a sentence. Every sentence must be in the Sentence List. Empty: every sentence of the lesson, a paragraph each." % BookletData.LINE_BREAK))
	var sentences_edit: TextEdit = _text_edit(_sentence_drafts.get(chapter, data.sentences_text(chapter)), 360,
			_on_sentences_changed.bind(chapter))
	_editor.add_child(sentences_edit)
	_add_missing_button = _button("Add the missing sentences, booklet only", _on_add_missing_pressed.bind(chapter, sentences_edit))
	_editor.add_child(_add_missing_button)
	_heading("Penguin tables")
	_editor.add_child(_label("One row per line, \"left | right\". Start a line with * for a bold row, which begins a new table; \\* for a cell that starts with a star."))
	_add_entries_editor(chapter, BookletData.Part.TABLES, 220)
	_heading("Writing page")
	_editor.add_child(_label("One item per line: a grapheme, a syllable or words (\"un vélo\"). Empty: no writing page."))
	_add_entries_editor(chapter, BookletData.Part.WRITING, 150)
	_heading("Fluency test")
	_editor.add_child(_label("One item per line, each printed in an earlier chapter. Empty: no fluency test."))
	_add_entries_editor(chapter, BookletData.Part.FLUENCY, 200)
	_heading("Stories")
	_editor.add_child(_label("Free text, paragraphs separated by an empty line. Words not studied yet are pointed out below."))
	for story: Dictionary in chapter.stories:
		_add_story_editor(chapter, story)
	_editor.add_child(_button("Add a story", func() -> void:
		chapter.stories.append({title = "", text = ""})
		_changed()
		_show_chapter(chapter)))

	_heading("To check")
	_problems_label = _label("")
	_problems_label.add_theme_color_override("font_color", WARNING_COLOR)
	_editor.add_child(_problems_label)
	_show_problems()


func _gp_checkboxes(chapter: BookletData.Chapter) -> HFlowContainer:
	var flow: HFlowContainer = HFlowContainer.new()
	var shown: Array[int] = data.lesson_gp_ids(chapter.lesson_id)
	for gp_id: int in chapter.gp_ids:
		if not gp_id in shown:
			shown.append(gp_id)
	for gp_id: int in shown:
		var check_box: CheckBox = CheckBox.new()
		check_box.text = data.gp_name(gp_id)
		check_box.add_theme_font_size_override("font_size", TEXT_SIZE)
		check_box.button_pressed = gp_id in chapter.gp_ids
		check_box.toggled.connect(func(pressed: bool) -> void:
			if pressed and not gp_id in chapter.gp_ids:
				chapter.gp_ids.append(gp_id)
			elif not pressed:
				chapter.gp_ids.erase(gp_id)
			_changed())
		flow.add_child(check_box)
	# A GP an earlier lesson taught, for a chapter such as "ui", whose u-8 is one
	# of lesson 7's exceptions.
	var earlier: OptionButton = _option_button()
	earlier.size_flags_horizontal = Control.SIZE_FILL
	earlier.custom_minimum_size.x = 700
	earlier.add_item("Add a GP of an earlier lesson…", -1)
	for gp_id: int in data.gps:
		var lesson: int = data.gps[gp_id].lesson
		if lesson >= 1 and lesson < chapter.lesson_nb and not gp_id in shown:
			earlier.add_item("%s (lesson %d)" % [data.gp_name(gp_id), lesson], gp_id)
	earlier.item_selected.connect(func(index: int) -> void:
		var gp_id: int = earlier.get_item_id(index)
		if gp_id >= 0:
			chapter.gp_ids.append(gp_id)
			_changed()
			_show_chapter(chapter))
	flow.add_child(earlier)
	return flow


func _image_picker(chapter: BookletData.Chapter) -> OptionButton:
	var picker: OptionButton = _option_button()
	picker.add_item("No teacher page", -1)
	var candidates: Array[int] = chapter.gp_ids.duplicate()
	if chapter.image_gp_id >= 0 and not chapter.image_gp_id in candidates:
		candidates.append(chapter.image_gp_id)
	for gp_id: int in candidates:
		var name: String = "Look & Learn image of " + data.gp_name(gp_id)
		if not data.has_image(gp_id):
			name += " (missing from the pack)"
		picker.add_item(name, gp_id)
	picker.select(maxi(picker.get_item_index(chapter.image_gp_id), 0))
	picker.item_selected.connect(func(index: int) -> void:
		chapter.image_gp_id = picker.get_item_id(index)
		_changed())
	return picker


func _add_override_row(grid: GridContainer, chapter: BookletData.Chapter, column: String) -> void:
	var own: CheckBox = CheckBox.new()
	own.text = BookletData.SETTINGS[column][0]
	own.add_theme_font_size_override("font_size", TEXT_SIZE)
	own.button_pressed = chapter.overrides.has(column)
	grid.add_child(own)
	var control: Control = _setting_control(column, data.value_of(chapter, column), func(value: float) -> void:
		chapter.overrides[column] = value
		own.set_pressed_no_signal(true)
		_changed())
	grid.add_child(control)
	grid.add_child(_label("language: " + _setting_text(column, data.settings.get(column, 0.0)), TEXT_SIZE, false))
	# Ticked again, the chapter's value is what the control shows, not the
	# language's, which value_of() returns once the override is gone.
	own.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			chapter.overrides[column] = _control_value(control)
		else:
			chapter.overrides.erase(column)
		_changed())


func _control_value(control: Control) -> float:
	if control is SpinBox:
		return (control as SpinBox).value
	var option: OptionButton = control as OptionButton
	return float(option.get_item_id(option.selected))


func _add_entries_editor(chapter: BookletData.Chapter, part: int, height: float) -> void:
	_editor.add_child(_text_edit(BookletData.entries_text(chapter.get_entries(part), part), height, func(text: String) -> void:
		chapter.entries[part] = BookletData.parse_entries(text, part)
		_changed()))


func _add_story_editor(chapter: BookletData.Chapter, story: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_editor.add_child(row)
	var title: LineEdit = LineEdit.new()
	title.text = story.title
	title.placeholder_text = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", TEXT_SIZE)
	title.text_changed.connect(func(text: String) -> void:
		story.title = text.strip_edges()
		_changed())
	row.add_child(title)
	row.add_child(_button("Delete story", func() -> void:
		chapter.stories.erase(story)
		_changed()
		_show_chapter(chapter)))
	_editor.add_child(_text_edit(story.text, 300, func(text: String) -> void:
		story.text = text.strip_edges()
		_changed()))


func _on_sentences_changed(text: String, chapter: BookletData.Chapter) -> void:
	var parsed: Dictionary = data.parse_sentences(text)
	chapter.sentences.assign(parsed.sentences)
	if (parsed.missing as PackedStringArray).is_empty():
		_sentence_drafts.erase(chapter)
	else:
		_sentence_drafts[chapter] = text
	_changed()


func _on_add_missing_pressed(chapter: BookletData.Chapter, sentences_edit: TextEdit) -> void:
	var text: String = sentences_edit.text
	var not_found: PackedStringArray = []
	var errors: PackedStringArray = []
	# Each one is known the moment it is added, so the same sentence typed twice
	# is added once.
	for missing: String in data.parse_sentences(text).missing:
		var result: Dictionary = data.add_booklet_sentence(missing)
		for word: String in result.missing:
			if not word in not_found:
				not_found.append(word)
		if not str(result.error).is_empty():
			errors.append(result.error)
	_on_sentences_changed(text, chapter)
	# Other chapters' drafts may name the sentences just added.
	_reparse_drafts()
	_show_problems()
	if not errors.is_empty():
		_status.text = "Some sentences could not be added: " + "; ".join(errors)
	elif not not_found.is_empty():
		_status.text = "Some sentences could not be added: add these words to the Word List first: " + ", ".join(not_found)
	else:
		_status.text = "Missing sentences added to the Sentence List, booklet only. They are written now: they stay there even if you leave without saving."


## Reads every pending draft again, keeping only those that still name a
## sentence the Sentence List lacks.
func _reparse_drafts() -> void:
	for chapter: BookletData.Chapter in _sentence_drafts.keys():
		var parsed: Dictionary = data.parse_sentences(_sentence_drafts[chapter])
		chapter.sentences.assign(parsed.sentences)
		if (parsed.missing as PackedStringArray).is_empty():
			_sentence_drafts.erase(chapter)


func _show_problems() -> void:
	if _chapter == null or _problems_label == null:
		return
	var found: PackedStringArray = data.save_errors()
	found.append_array(data.problems(_chapter))
	var missing: PackedStringArray = data.parse_sentences(_sentence_drafts[_chapter]).missing if _sentence_drafts.has(_chapter) else PackedStringArray()
	for text: String in missing:
		found.insert(0, "Sentence \"%s\" is not in the Sentence List" % text)
	_add_missing_button.visible = not missing.is_empty()
	_problems_label.text = "\n".join(found) if not found.is_empty() else "Nothing to check."

#endregion

func _changed() -> void:
	_dirty = true
	_status.text = "Not saved."
	_problems_timer.start()


func _on_save_pressed() -> void:
	_reparse_drafts()
	for chapter: BookletData.Chapter in _sentence_drafts:
		_status.text = "Lesson %d, chapter %d names sentences the Sentence List does not have: add them, or remove them, before saving." % [chapter.lesson_nb, chapter.position + 1]
		return
	var error: String = data.save_to_database()
	if not error.is_empty():
		_status.text = error
		return
	_dirty = false
	_status.text = "Saved."


func _on_back_pressed() -> void:
	if _dirty:
		_status.text = "Not saved: press Save first, or Back again to leave without saving."
		_dirty = false
		return
	get_tree().change_scene_to_file(MENU_SCENE)
