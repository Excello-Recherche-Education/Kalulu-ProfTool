class_name BookletPreview
extends VBoxContainer
## The Booklets screen's preview: the selected chapter's pages, in the series
## and version chosen above them, exactly as the booklet prints them, and what
## the generator says about that chapter under them.
##
## The pages are Kalulu-Booklets' own (res://booklets/, BookletLayout), drawn
## on a CanvasSurface instead of a PDF. A chapter's pages depend on the chapters
## before it in its booklet (an automatic chapter does not repeat a sentence an
## earlier one printed, and the page numbers run on), so the whole booklet is
## laid out and the chapter's pages are shown (Page.chapter_ids). The chapters'
## content is kept between layouts and worked out again only for a chapter that
## changed (BookletContent.booklet()'s cache).

const TEXT_SIZE: int = 36
const NOTE_COLOR: Color = Color(1.0, 0.6, 0.1)
## Room between two pages, and around them, in pixels.
const PAGE_GAP: float = 24.0
const PAGE_BORDER: Color = Color(0.6, 0.6, 0.6)

## What the screen edits.
var data: BookletData
## The fonts folder of the Kalulu-Languages checkout the language was opened
## from, "" for none (BookletData.fonts_folder()).
var checkout_fonts: String = ""

var _chapter: BookletData.Chapter = null
var _series_picker: OptionButton
var _version_picker: OptionButton
var _info: Label
var _scroll: ScrollContainer
var _pages: Control
var _notes: Label
var _item: RID
## Series -> chapter ID -> [ChapterContent, notes], for BookletContent.booklet().
var _content: Dictionary = {}
var _lists_version: int = -1
## The last layout, kept to draw it again when the panel is resized, and the
## indexes of the chapter's pages in it.
var _laid_out: BookletLayout = null
var _shown: Array[int] = []
var _folios: Array[int] = []
var _warmed: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 20)
	add_child(row)
	var title: Label = Label.new()
	title.text = "Preview"
	title.add_theme_font_size_override("font_size", 48)
	row.add_child(title)
	_series_picker = _picker()
	row.add_child(_series_picker)
	_version_picker = _picker()
	row.add_child(_version_picker)
	_info = _label("")
	add_child(_info)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.resized.connect(_draw_pages)
	add_child(_scroll)
	_pages = Control.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_pages)
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, _pages.get_canvas_item())
	_notes = _label("")
	_notes.add_theme_color_override("font_color", NOTE_COLOR)
	add_child(_notes)
	show_chapter(null)


func _exit_tree() -> void:
	_release()
	if _item.is_valid():
		RenderingServer.free_rid(_item)
		_item = RID()


func _picker() -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.fit_to_longest_item = false
	picker.add_theme_font_size_override("font_size", TEXT_SIZE)
	picker.get_popup().add_theme_font_size_override("font_size", TEXT_SIZE)
	picker.item_selected.connect(func(_index: int) -> void: refresh())
	return picker


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	return label


## Shows `chapter`'s pages; null shows nothing, with the language settings.
func show_chapter(chapter: BookletData.Chapter) -> void:
	_chapter = chapter
	refresh()


## The selected chapter changed: its content is worked out again.
func chapter_changed() -> void:
	if _chapter != null:
		var chapter_id: int = data.pack_id_of(_chapter)
		for series: String in _content:
			_content[series].erase(chapter_id)
	refresh()


## Something every chapter's content may depend on changed (the language's
## settings or fonts, the chapters' order, a save giving new chapters their
## IDs): everything is worked out again.
func forget() -> void:
	_content.clear()
	refresh()


## Lays the selected chapter's booklet out again and shows its pages.
func refresh() -> void:
	if not is_node_ready():
		return
	_release()
	_shown.clear()
	if _chapter == null:
		_show_message("Select a chapter to see its pages as they print.")
		return
	if not _warmed:
		# The first layout shapes and caches every glyph the booklet uses, which
		# takes a few seconds: say so before the screen stops for it.
		_warmed = true
		_show_message("Preparing the preview…")
		await get_tree().process_frame
		await get_tree().process_frame
		if _chapter == null:
			return
	var pack: BookletPack = data.to_booklet_pack()
	if pack == null:
		_show_message("No preview: %s" % data.pack_error)
		return
	if data.lists_version != _lists_version:
		_lists_version = data.lists_version
		_content.clear()
	var fonts_folder: String = data.fonts_folder(checkout_fonts)
	if fonts_folder.is_empty():
		var replaced: Dictionary = {}
		for role: String in pack.fonts:
			replaced[role] = pack.fonts[role].file
		_show_message("No preview: %s" % FontSet.find("", replaced, "res://fonts")["error"])
		return
	var replaced_files: Dictionary = {}
	for role: String in pack.fonts:
		replaced_files[role] = pack.fonts[role].file
	var fonts: FontSet = FontSet.from_folder(fonts_folder, replaced_files)
	_fill_pickers(pack)
	var series: String = _series_picker.get_item_metadata(_series_picker.selected)
	var version: BookletVersion = BookletVersion.named(_version_picker.get_item_metadata(_version_picker.selected))
	if not _content.has(series):
		_content[series] = {}
	var chapter_id: int = data.pack_id_of(_chapter)
	var booklet: BookletContent.Booklet = BookletContent.booklet(pack, _chapter.booklet, series, _content[series])
	var chosen: Variant = null
	if not version.adapted.is_empty():
		# An adapted version prints the sentences the base booklet chose.
		var base: BookletLayout = BookletLayout.new(BookletContent.booklet(pack, _chapter.booklet, series,
				_content[series]), fonts)
		base.run()
		chosen = base.chosen
		base.release()
	_laid_out = BookletWriter.layout_for(booklet, fonts, version, chosen)
	var pages: Array[BookletLayout.Page] = _laid_out.run()
	_folios = BookletWriter.folios(pages)
	for index: int in range(pages.size()):
		if pages[index].chapter_ids.has(chapter_id):
			_shown.append(index)
	var prefix: String = data.chapter_name(_chapter) + ": "
	var notes: PackedStringArray = []
	for note: String in booklet.notes:
		if note.begins_with(prefix):
			notes.append("• " + note.trim_prefix(prefix))
	_notes.text = "\n".join(notes)
	if _shown.is_empty():
		_info.text = "Booklet %d prints nothing of this chapter." % _chapter.booklet
	else:
		_info.text = "Booklet %d, page %s of %d." % [_chapter.booklet, _page_span(), pages.size()]
	_draw_pages()


func _page_span() -> String:
	var first: int = _shown[0] + 1
	var last: int = _shown[-1] + 1
	return str(first) if first == last else "%d to %d" % [first, last]


func _fill_pickers(pack: BookletPack) -> void:
	var series_names: Array[String] = pack.series()
	var version_names: Array[String] = pack.versions()
	_refill(_series_picker, series_names, func(name: String) -> String: return name.capitalize() + " series")
	_series_picker.visible = series_names.size() > 1
	_refill(_version_picker, version_names, func(name: String) -> String:
		if name == "base":
			return "Base booklet"
		return "%s version" % BookletData.VERSIONS[BookletPack.VERSION_COLUMNS[name]][0])


## Fills a picker with `names` when they changed, keeping the one selected.
func _refill(picker: OptionButton, names: Array[String], text_of: Callable) -> void:
	var current: Array[String] = []
	for index: int in range(picker.item_count):
		current.append(str(picker.get_item_metadata(index)))
	if current == names:
		return
	var selected: String = str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
	picker.clear()
	for name: String in names:
		picker.add_item(text_of.call(name))
		picker.set_item_metadata(picker.item_count - 1, name)
		if name == selected:
			picker.select(picker.item_count - 1)
	if picker.selected < 0 and picker.item_count > 0:
		picker.select(0)


func _show_message(text: String) -> void:
	_info.text = text
	_notes.text = ""
	RenderingServer.canvas_item_clear(_item)
	_pages.custom_minimum_size = Vector2.ZERO


## Draws the chapter's pages one under the other, as wide as the panel allows.
func _draw_pages() -> void:
	if _laid_out == null or not _item.is_valid():
		return
	RenderingServer.canvas_item_clear(_item)
	var width: float = maxf(_scroll.size.x - 2.0 * PAGE_GAP, 200.0)
	var scale: float = width / BookletWriter.A5.x
	var page_size: Vector2 = BookletWriter.A5 * scale
	var surface: CanvasSurface = CanvasSurface.new(BookletWriter.A5, _item, scale, Vector2(PAGE_GAP, PAGE_GAP),
			PAGE_GAP)
	for shown: int in range(_shown.size()):
		var top: float = PAGE_GAP + surface.page_offset(shown)
		var frame: Rect2 = Rect2(PAGE_GAP, top, page_size.x, page_size.y)
		RenderingServer.canvas_item_add_rect(_item, frame, Color.WHITE)
		var index: int = _shown[shown]
		BookletWriter.draw_page(surface, _laid_out.pages[index], _folios[index], _laid_out)
		surface.end_page()
		var corners: PackedVector2Array = [frame.position, Vector2(frame.end.x, frame.position.y), frame.end,
				Vector2(frame.position.x, frame.end.y), frame.position]
		RenderingServer.canvas_item_add_polyline(_item, corners, PackedColorArray([PAGE_BORDER]), 2.0)
	_pages.custom_minimum_size = Vector2(0.0, PAGE_GAP + _shown.size() * (page_size.y + PAGE_GAP))


## Lets go of the last layout: its pages' steps hold it (BookletLayout.release()).
func _release() -> void:
	if _laid_out != null:
		_laid_out.release()
		_laid_out = null
