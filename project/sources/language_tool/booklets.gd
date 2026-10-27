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

## Most matches a search box lists; typing more narrows them.
const MATCHES_SHOWN: int = 60
const BREAK_NAMES: Dictionary[int, String] = {
	BookletData.Break.NEW_PARAGRAPH: "New paragraph",
	BookletData.Break.NEW_LINE: "New line",
	BookletData.Break.SAME_LINE: "Same line",
}

var data: BookletData = BookletData.new()
var _chapter: BookletData.Chapter = null
var _dirty: bool = false

var _chapter_list: ItemList
var _lesson_picker: OptionButton
var _editor: VBoxContainer
var _status: Label
var _problems_label: Label
## Part -> the label above its picks that says when they are not the count,
## and the one that says when one is picked more than once.
var _count_warnings: Dictionary[int, Label] = {}
var _repeat_infos: Dictionary[int, Label] = {}
var _problems_timer: Timer
var _font_dialog: FileDialog
## The lists choosing each role's font, whose items are the fonts' names.
var _font_options: Array[OptionButton] = []
## Font file path -> the font loaded from it for a preview, null when it cannot be.
var _loaded_fonts: Dictionary[String, FontFile] = {}


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


func _warning_label(text: String) -> Label:
	var label: Label = _label(text)
	label.add_theme_color_override("font_color", WARNING_COLOR)
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
	_count_warnings.clear()
	_repeat_infos.clear()


func _spin_box(value: float, lowest: float, highest: float, real: bool, on_change: Callable) -> SpinBox:
	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = lowest
	spin_box.max_value = highest
	spin_box.step = 0.01 if real else 1.0
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
	# A short box and a wrapped label: a CheckBox's text never wraps, and a long
	# one widened the whole form past the screen, Save included.
	var cursive: CheckBox = CheckBox.new()
	cursive.text = "Written in cursive too"
	cursive.add_theme_font_size_override("font_size", TEXT_SIZE)
	cursive.button_pressed = data.settings.get("Cursive", 1.0) != 0.0
	cursive.toggled.connect(func(pressed: bool) -> void:
		data.settings["Cursive"] = float(pressed)
		_changed())
	_editor.add_child(cursive)
	_editor.add_child(_label("Ticked: titles, sentences and writing pages are also printed in cursive. Unticked: everything is printed in script, and the sentence fonts below are ignored."))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	_editor.add_child(grid)
	for column: String in BookletData.SETTINGS:
		grid.add_child(_label(BookletData.SETTINGS[column][0], TEXT_SIZE, false))
		grid.add_child(_setting_control(column, data.settings.get(column, 0.0), func(value: float) -> void:
			data.settings[column] = value
			_changed()))
	_show_fonts()


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
	_editor.add_child(_label("Picked from the Syllable List, in order. The chapter prints \"Syllables printed\" of them: past that number the last ones are left out; short of it, the rest is chosen from the syllables the lesson can read that hold one of its GPs, booklet-only ones first, then in the pack's order, repeated if there are still too few."))
	_add_picker(chapter, BookletData.Part.SYLLABLES)
	_heading("Words")
	_editor.add_child(_label("Picked from the Word List, in order, and printed as the box says: add an article or a capital there (\"la Lune\" for \"lune\"), as long as the word stays. \"Words printed\" works as for syllables."))
	_add_picker(chapter, BookletData.Part.WORDS)
	_heading("Sentences")
	_editor.add_child(_label("Picked from the Sentence List, in order, each after a new paragraph, a new line, or on the same line as the one before (%s is a line break inside a sentence). Alternating: script and cursive take turns, paragraph by paragraph. \"Sentence pages\": -1 prints none, 0 only what fits on the chapter page, 1 or more that many pages more. Nothing picked: as many sentences as fit are chosen, each whole and a paragraph of its own, from those the lesson can read, the ones holding the chapter's GPs first, booklet-only ones first, then in the pack's order." % BookletData.LINE_BREAK))
	_add_sentence_picker(chapter)
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


func _show_problems() -> void:
	if _chapter == null or _problems_label == null:
		return
	var found: PackedStringArray = data.save_errors()
	found.append_array(data.problems(_chapter))
	# A count changed under "Own settings" changes the warnings too.
	for part: int in _count_warnings:
		_show_count_warning(_chapter, part)
	_problems_label.text = "\n".join(found) if not found.is_empty() else "Nothing to check."

#endregion

#region Fonts

## The Fonts part of the language settings: the fonts added to the language, and
## which of them replaces each default one, each with a preview of the pack's
## text in it and the characters it lacks.
func _show_fonts() -> void:
	_heading("Fonts")
	_editor.add_child(_label("The booklets print with Mulish (script) and Marelle (cursive). Another font can replace any of the four below, everywhere in this language's booklets: put it in Kalulu-Languages' fonts folder first, with its license in fonts/LICENSE.md, then add it here and choose what it replaces."))
	if _fonts_folder().is_empty():
		_editor.add_child(_warning_label("No preview: open this language from its language.db in a Kalulu-Languages checkout, and the Prof Tool finds the fonts folder beside it."))

	_font_options.clear()
	for font: BookletData.BookletFont in data.fonts:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		_editor.add_child(row)
		var font_name: LineEdit = LineEdit.new()
		font_name.text = font.name
		font_name.custom_minimum_size.x = 600
		font_name.add_theme_font_size_override("font_size", TEXT_SIZE)
		font_name.text_changed.connect(func(text: String) -> void:
			font.name = text.strip_edges()
			for option: OptionButton in _font_options:
				option.set_item_text(option.get_item_index(data.fonts.find(font) + 1), font.name)
			_changed())
		row.add_child(font_name)
		var file: Label = _label("fonts/" + font.file, TEXT_SIZE, false)
		file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		file.clip_text = true
		row.add_child(file)
		row.add_child(_button("Remove", func() -> void:
			data.remove_font(font)
			_changed()
			_show_settings()))
	_editor.add_child(_button("Add custom font...", _on_add_font_pressed))

	for column: String in BookletData.FONT_ROLES:
		var role: Array = BookletData.FONT_ROLES[column]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 30)
		_editor.add_child(row)
		var role_label: Label = _label(role[0], TEXT_SIZE, false)
		role_label.custom_minimum_size.x = 300
		row.add_child(role_label)
		var option: OptionButton = _option_button()
		option.add_item("Default: " + str(role[1]), 0)
		for index: int in range(data.fonts.size()):
			option.add_item(data.fonts[index].name, index + 1)
		var chosen: BookletData.BookletFont = data.font_choices.get(column, null)
		option.select(0 if chosen == null else data.fonts.find(chosen) + 1)
		row.add_child(option)
		_font_options.append(option)
		var preview: Label = _label("")
		var missing: Label = _warning_label("")
		_editor.add_child(preview)
		_editor.add_child(missing)
		_show_font_preview(column, preview, missing)
		option.item_selected.connect(func(index: int) -> void:
			var id: int = option.get_item_id(index)
			if id == 0:
				data.font_choices.erase(column)
			else:
				data.font_choices[column] = data.fonts[id - 1]
			_changed()
			_show_font_preview(column, preview, missing))


## Shows the pack's text in the font a role prints with, and the characters of
## the pack it lacks, which the booklets could not print.
func _show_font_preview(column: String, preview: Label, missing: Label) -> void:
	var chosen: BookletData.BookletFont = data.font_choices.get(column, null)
	var file: String = BookletData.FONT_ROLES[column][2] if chosen == null else chosen.file
	missing.text = ""
	var folder: String = _fonts_folder()
	if folder.is_empty():
		preview.visible = false
		return
	var font: FontFile = _load_font(folder.path_join(file))
	preview.visible = true
	if font == null:
		preview.remove_theme_font_override("font")
		preview.text = "fonts/%s cannot be read here: it is not in %s, or it is not a font." % [file, folder]
		preview.add_theme_color_override("font_color", WARNING_COLOR)
		return
	preview.remove_theme_color_override("font_color")
	preview.add_theme_font_override("font", font)
	preview.add_theme_font_size_override("font_size", HEADING_SIZE)
	var characters: PackedStringArray = data.pack_characters()
	# Spaced, so that the line wraps: unbroken, it would widen the whole form.
	preview.text = _font_sample() + "\n" + " ".join(characters)
	var lacking: PackedStringArray = []
	for character: String in characters:
		if _lacks(font, character):
			lacking.append(character)
	if not lacking.is_empty():
		missing.text = "This font has no %s: the booklets cannot print %s." % [
				" ".join(lacking), "it" if lacking.size() == 1 else "them"]
	if column == "CursiveFontID" and data.settings.get("Cursive", 1.0) == 0.0:
		missing.text = ("%s\n" % missing.text if not missing.text.is_empty() else "") + "Not printed: this language is written in script only (see the box above)."


## A sentence of the pack, the first one the booklets could start with.
func _font_sample() -> String:
	var first: int = -1
	for sentence_id: int in data.sentences:
		if first < 0 or sentence_id < first:
			first = sentence_id
	return str(data.sentences[first].text).replace("\n", " ") if first >= 0 else ""


## Whether a font cannot print a character. Shaped rather than looked up: a
## shaping engine, the generator's included, prints a letter the font has no
## glyph for from its parts when it has those ("á" as "a" and a combining acute,
## which is how Marelle prints Spanish), so only a glyph no font gives is lacking.
func _lacks(font: FontFile, character: String) -> bool:
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var shaped: RID = text_server.create_shaped_text()
	text_server.shaped_text_add_string(shaped, character, font.get_rids(), TEXT_SIZE)
	var lacking: bool = false
	for glyph: Dictionary in text_server.shaped_text_get_glyphs(shaped):
		if not (glyph.font_rid as RID).is_valid():
			lacking = true
	text_server.free_rid(shaped)
	return lacking


## A font for the previews, without the system's fonts behind it: a character it
## lacks shows as a box, as it would be missing on paper.
func _load_font(path: String) -> FontFile:
	if not _loaded_fonts.has(path):
		var font: FontFile = null
		if FileAccess.file_exists(path):
			font = FontFile.new()
			if font.load_dynamic_font(path) != OK:
				font = null
			else:
				font.allow_system_fallback = false
		_loaded_fonts[path] = font
	return _loaded_fonts[path]


## The fonts folder of the Kalulu-Languages checkout this language was opened
## from, or "" when it was not opened from one.
func _fonts_folder() -> String:
	var pack_folder: String = ProfToolSave.load_or_create().pack_folders.get(Database.language, "")
	if pack_folder.is_empty():
		return ""
	var checkout: String = pack_folder.get_base_dir()
	if not FileAccess.file_exists(checkout.path_join("SCHEMA.md")) or not DirAccess.dir_exists_absolute(checkout.path_join("fonts")):
		return ""
	return checkout.path_join("fonts")


func _on_add_font_pressed() -> void:
	if _font_dialog == null:
		_font_dialog = FileDialog.new()
		_font_dialog.title = "Add a custom font"
		_font_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_font_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_font_dialog.filters = PackedStringArray(["*.ttf, *.otf ; TrueType or OpenType fonts"])
		_font_dialog.size = Vector2i(1500, 1000)
		_font_dialog.file_selected.connect(_on_font_file_selected)
		add_child(_font_dialog)
	var folder: String = _fonts_folder()
	if not folder.is_empty():
		_font_dialog.current_dir = folder
	_font_dialog.popup_centered()


func _on_font_file_selected(path: String) -> void:
	var font: FontFile = FontFile.new()
	if font.load_dynamic_font(path) != OK:
		_status.text = "Not added: %s is not a font this Prof Tool can read." % path.get_file()
		return
	var display_name: String = ("%s %s" % [font.get_font_name(), font.get_font_style_name()]).strip_edges()
	var result: Dictionary = data.add_font(path, display_name)
	if result.font == null:
		_status.text = "Not added: " + str(result.error)
		return
	_changed()
	_show_settings()

#endregion

#region Picking from the pack

## A search box over one of the pack's lists: typing lists the matches below it,
## and clicking one, or Enter for the first, picks it. matches(query) returns
## [label, value, available] arrays; one not available is shown in orange.
func _search_box(placeholder: String, matches: Callable, on_pick: Callable) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	var search: LineEdit = LineEdit.new()
	search.placeholder_text = placeholder
	search.add_theme_font_size_override("font_size", TEXT_SIZE)
	box.add_child(search)
	var results: ItemList = ItemList.new()
	results.custom_minimum_size.y = 320
	results.add_theme_font_size_override("font_size", TEXT_SIZE)
	results.visible = false
	box.add_child(results)
	search.text_changed.connect(func(query: String) -> void:
		results.clear()
		if not query.strip_edges().is_empty():
			for found: Array in matches.call(query.strip_edges()):
				var index: int = results.add_item(found[0])
				results.set_item_metadata(index, found[1])
				if not found[2]:
					results.set_item_custom_fg_color(index, WARNING_COLOR)
		results.visible = results.item_count > 0)
	results.item_selected.connect(func(index: int) -> void:
		on_pick.call(results.get_item_metadata(index))
		results.deselect_all())
	search.text_submitted.connect(func(_text: String) -> void:
		if results.item_count > 0:
			on_pick.call(results.get_item_metadata(0)))
	return box


## The syllables or words matching a query: those the chapter can print first,
## then those starting with it, then the shortest.
func _item_matches(query: String, chapter: BookletData.Chapter, part: int) -> Array[Array]:
	var wanted: String = query.to_lower()
	var ranked: Array[Array] = []
	var list: Array[Dictionary] = data.syllable_list if part == BookletData.Part.SYLLABLES else data.word_list
	for index: int in range(list.size()):
		var item: Dictionary = list[index]
		var lowered: String = str(item.text).to_lower()
		if not wanted in lowered:
			continue
		var notes: PackedStringArray = _readability_notes(int(item.lesson), chapter)
		if item.exception:
			notes.append("exception")
		if item.booklet_only:
			notes.append("booklet only")
		var available: bool = notes.is_empty() or notes == PackedStringArray(["booklet only"])
		var label: String = item.text if notes.is_empty() else "%s   (%s)" % [item.text, ", ".join(notes)]
		ranked.append([[int(not available), int(not lowered.begins_with(wanted)), lowered.length(), index], label, item.text, available])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var found: Array[Array] = []
	for entry: Array in ranked.slice(0, MATCHES_SHOWN):
		found.append(entry.slice(1))
	return found


func _readability_notes(lesson: int, chapter: BookletData.Chapter) -> PackedStringArray:
	if lesson < 0:
		return PackedStringArray(["never readable"])
	if lesson > chapter.lesson_nb:
		return PackedStringArray(["readable from lesson %d" % lesson])
	return PackedStringArray()


func _add_picker(chapter: BookletData.Chapter, part: int) -> void:
	var warning: Label = _label("")
	warning.add_theme_color_override("font_color", WARNING_COLOR)
	_count_warnings[part] = warning
	_editor.add_child(warning)
	var info: Label = _label("")
	_repeat_infos[part] = info
	_editor.add_child(info)
	var rows: VBoxContainer = VBoxContainer.new()
	_editor.add_child(rows)
	_fill_entry_rows(rows, chapter, part)
	var placeholder: String = "Search the %s List to add…" % ("Syllable" if part == BookletData.Part.SYLLABLES else "Word")
	_editor.add_child(_search_box(placeholder, _item_matches.bind(chapter, part), func(text: String) -> void:
		var entry: Dictionary = {text = text, text2 = "", header = false}
		if part == BookletData.Part.WORDS:
			# What the printed text must keep holding; a list word that is cut
			# into several (an apostrophe) is not checked.
			var pieces: PackedStringArray = BookletData.words_of(text)
			entry.base = pieces[0] if pieces.size() == 1 else ""
		chapter.get_entries(part).append(entry)
		_changed()
		_fill_entry_rows(rows, chapter, part)))
	_show_count_warning(chapter, part)


func _fill_entry_rows(rows: VBoxContainer, chapter: BookletData.Chapter, part: int) -> void:
	_clear_children(rows)
	var entries: Array = chapter.get_entries(part)
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		rows.add_child(row)
		row.add_child(_label("%d." % (index + 1), TEXT_SIZE, false))
		var list_lesson: int = -1
		if part == BookletData.Part.WORDS:
			var edit: LineEdit = LineEdit.new()
			edit.text = entry.text
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.add_theme_font_size_override("font_size", TEXT_SIZE)
			row.add_child(edit)
			var problem: Label = _label(BookletData.word_entry_problem(entry))
			problem.add_theme_color_override("font_color", WARNING_COLOR)
			problem.visible = not problem.text.is_empty()
			edit.text_changed.connect(func(text: String) -> void:
				entry.text = text.strip_edges()
				problem.text = BookletData.word_entry_problem(entry)
				problem.visible = not problem.text.is_empty()
				_changed())
			list_lesson = data.word_lessons.get(str(entry.get("base", "")), -1)
			var base: String = entry.get("base", "")
			row.add_child(_label("from \"%s\"" % base if not base.is_empty() else "in no list", TEXT_SIZE, false))
			rows.add_child(problem)
		else:
			var text: Label = _label(entry.text, TEXT_SIZE, false)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
			list_lesson = data.syllable_lessons.get(str(entry.text).to_lower(), -1)
		var notes: Label = _label(", ".join(_readability_notes(list_lesson, chapter)), TEXT_SIZE, false)
		notes.add_theme_color_override("font_color", WARNING_COLOR)
		row.add_child(notes)
		row.add_child(_button("Up", _move_entry.bind(rows, chapter, part, index, -1)))
		row.add_child(_button("Down", _move_entry.bind(rows, chapter, part, index, 1)))
		row.add_child(_button("Remove", func() -> void:
			entries.remove_at(index)
			_changed()
			_fill_entry_rows(rows, chapter, part)))
	_show_count_warning(chapter, part)


func _move_entry(rows: VBoxContainer, chapter: BookletData.Chapter, part: int, index: int, direction: int) -> void:
	var entries: Array = chapter.get_entries(part)
	var target: int = index + direction
	if target < 0 or target >= entries.size():
		return
	var moved: Variant = entries[index]
	entries[index] = entries[target]
	entries[target] = moved
	_changed()
	_fill_entry_rows(rows, chapter, part)


## The warning sign above a chapter's syllables or words when the picks are not
## the count printed, nothing when they are or when nothing is picked; and the
## information that one is picked more than once.
func _show_count_warning(chapter: BookletData.Chapter, part: int) -> void:
	if not _count_warnings.has(part):
		return
	var warning: String = data.count_warning(chapter, part)
	_count_warnings[part].text = "⚠ " + warning if not warning.is_empty() else ""
	_count_warnings[part].visible = not warning.is_empty()
	var info: String = data.repeat_info(chapter, part)
	_repeat_infos[part].text = "ℹ " + info if not info.is_empty() else ""
	_repeat_infos[part].visible = not info.is_empty()


func _add_sentence_picker(chapter: BookletData.Chapter) -> void:
	var rows: VBoxContainer = VBoxContainer.new()
	_editor.add_child(rows)
	_fill_sentence_rows(rows, chapter)
	_editor.add_child(_search_box("Search the Sentence List to add…", _sentence_matches.bind(chapter), func(value: Variant) -> void:
		var sentence_id: int = int(value) if value is int else _add_new_sentence(str(value.new))
		if sentence_id < 0:
			return
		var brk: int = BookletData.Break.NEW_PARAGRAPH
		if not chapter.sentences.is_empty():
			brk = int(chapter.sentences[-1].brk)
		chapter.sentences.append({id = sentence_id, brk = brk})
		_changed()
		_fill_sentence_rows(rows, chapter)))


## The sentences matching a query, those the chapter can read first; and, when
## none is the query itself, the offer to add it as a booklet-only sentence.
func _sentence_matches(query: String, chapter: BookletData.Chapter) -> Array[Array]:
	var wanted: String = BookletData.normalize(query)
	var ranked: Array[Array] = []
	for sentence_id: int in data.sentences:
		var sentence: Dictionary = data.sentences[sentence_id]
		var lowered: String = BookletData.normalize(sentence.text)
		if not wanted in lowered:
			continue
		var notes: PackedStringArray = _readability_notes(int(sentence.lesson), chapter)
		var available: bool = notes.is_empty()
		if sentence.booklet_only:
			notes.append("booklet only")
		var text: String = str(sentence.text).replace("\n", BookletData.LINE_BREAK)
		var label: String = text if notes.is_empty() else "%s   (%s)" % [text, ", ".join(notes)]
		ranked.append([[int(not available), int(not lowered.begins_with(wanted)), lowered.length(), sentence_id], label, sentence_id, available])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var found: Array[Array] = []
	for entry: Array in ranked.slice(0, MATCHES_SHOWN):
		found.append(entry.slice(1))
	if data.find_sentence(query) < 0:
		found.append(["Add \"%s\" to the Sentence List, booklet only" % query, {new = query}, true])
	return found


## Adds a sentence to the Sentence List, booklet-only, and returns its ID; -1,
## and why in the status line, when it cannot be.
func _add_new_sentence(text: String) -> int:
	var result: Dictionary = data.add_booklet_sentence(text)
	if not str(result.error).is_empty():
		_status.text = "Not added: " + str(result.error)
		return -1
	if not (result.missing as PackedStringArray).is_empty():
		_status.text = "Not added: add these words to the Word List first: " + ", ".join(result.missing)
		return -1
	_status.text = "Added to the Sentence List, booklet only. It is written now: it stays there even if you leave without saving."
	return data.find_sentence(text)


func _fill_sentence_rows(rows: VBoxContainer, chapter: BookletData.Chapter) -> void:
	_clear_children(rows)
	for index: int in range(chapter.sentences.size()):
		var item: Dictionary = chapter.sentences[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		rows.add_child(row)
		var brk: OptionButton = _option_button()
		brk.size_flags_horizontal = Control.SIZE_FILL
		brk.custom_minimum_size.x = 420
		for value: int in BREAK_NAMES:
			brk.add_item(BREAK_NAMES[value], value)
		# The first sentence starts a paragraph, whatever it says.
		brk.select(brk.get_item_index(BookletData.Break.NEW_PARAGRAPH if index == 0 else int(item.brk)))
		brk.disabled = index == 0
		brk.item_selected.connect(func(selected: int) -> void:
			item.brk = brk.get_item_id(selected)
			_changed())
		row.add_child(brk)
		var sentence: Dictionary = data.sentences.get(item.id, {})
		var text: Label = _label(str(sentence.get("text", "?")).replace("\n", BookletData.LINE_BREAK), TEXT_SIZE, false)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.tooltip_text = text.text
		text.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(text)
		var notes: PackedStringArray = _readability_notes(int(sentence.get("lesson", -1)), chapter)
		var notes_label: Label = _label(", ".join(notes), TEXT_SIZE, false)
		notes_label.add_theme_color_override("font_color", WARNING_COLOR)
		row.add_child(notes_label)
		row.add_child(_button("Up", _move_sentence.bind(rows, chapter, index, -1)))
		row.add_child(_button("Down", _move_sentence.bind(rows, chapter, index, 1)))
		row.add_child(_button("Remove", func() -> void:
			chapter.sentences.remove_at(index)
			_changed()
			_fill_sentence_rows(rows, chapter)))


func _move_sentence(rows: VBoxContainer, chapter: BookletData.Chapter, index: int, direction: int) -> void:
	var target: int = index + direction
	if target < 0 or target >= chapter.sentences.size():
		return
	var moved: Dictionary = chapter.sentences[index]
	chapter.sentences[index] = chapter.sentences[target]
	chapter.sentences[target] = moved
	_changed()
	_fill_sentence_rows(rows, chapter)


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

#endregion


func _changed() -> void:
	_dirty = true
	_status.text = "Not saved."
	_problems_timer.start()


func _on_save_pressed() -> void:
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
