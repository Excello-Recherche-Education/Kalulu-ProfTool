class_name BookletData
extends RefCounted
## What the reading booklets of the open pack contain, read from and written to
## its Booklet* tables (Kalulu-Languages SCHEMA.md, "The reading booklets").
##
## The Booklets screen edits one of these and saves it back; nothing else in the
## Prof Tool reads the tables. Kalulu-Booklets prints the booklets from them.
##
## Chapters follow the app's lessons: they are kept sorted by their lesson's
## number, then by their position among the chapters of that lesson.

## BookletEntries.Part values.
enum Part { SYLLABLES = 1, WORDS = 2, WRITING = 3, TABLES = 4, FLUENCY = 5 }

## The parts whose entries are picked from any of the pack's lists -- a GP's
## grapheme, a syllable, a word or a sentence -- and may then be printed
## differently, as long as they still hold what was picked.
const PACK_PICKED_PARTS: Array[int] = [Part.WRITING, Part.TABLES, Part.FLUENCY]
const PART_NAMES: Dictionary[int, String] = {
	Part.SYLLABLES: "syllables", Part.WORDS: "words", Part.WRITING: "writing page",
	Part.TABLES: "tables", Part.FLUENCY: "fluency test",
}

## BookletSentences.Break values: what comes before a sentence.
enum Break { SAME_LINE = 0, NEW_LINE = 1, NEW_PARAGRAPH = 2 }

## The settings a chapter can override, in the order the screen shows them:
## column -> [label, lowest, highest, is_real]. The ranges are the validator's
## (Kalulu-Languages SCHEMA.md rule 8).
const SETTINGS: Dictionary[String, Array] = {
	"SyllableCount": ["Syllables printed", 0, 999, false],
	"SyllableColumns": ["Syllable columns", 1, 10, false],
	"WordCount": ["Words printed", 0, 999, false],
	"WordColumns": ["Word columns", 1, 10, false],
	"UppercaseProportion": ["Share in capitals (0-1)", 0, 1, true],
	"SentenceFont": ["Sentence font", 0, 2, false],
	"SentenceFirstFont": ["First paragraph's font", 1, 2, false],
	"SentencePages": ["Sentence pages (-1 none, 0 chapter page only)", -1, 99, false],
	"WritingModels": ["Writing: black copies", 0, 10, false],
	"WritingTracings": ["Writing: grey copies to trace", 0, 10, false],
}
const SENTENCE_FONTS: PackedStringArray = ["Alternating", "Script only", "Cursive only"]
const FIRST_FONTS: PackedStringArray = ["", "Script", "Cursive"]

## The fonts a language can replace, in the order the screen shows them:
## BookletSettings column -> [label, the default font's name, its file in
## Kalulu-Languages' fonts/]. The generator prints with these when the column is
## NULL (Kalulu-Booklets fonts.py).
const FONT_ROLES: Dictionary[String, Array] = {
	"ScriptFontID": ["Script", "Mulish (Kalulu), regular", "mulish/kalulu_mulish_regular.otf"],
	"ScriptBoldFontID": ["Script bold", "Mulish (Kalulu), bold", "mulish/kalulu_mulish_bold.otf"],
	"ScriptBlackFontID": ["Script black", "Mulish (Kalulu), black", "mulish/kalulu_mulish_black.otf"],
	"CursiveFontID": ["Cursive", "Marelle", "marelle/Marelle-Regular.ttf"],
}
## What a font file must end with to be printed: TrueType or OpenType.
const FONT_EXTENSIONS: PackedStringArray = ["ttf", "otf"]

## How the Booklets screen shows a line break that is part of a sentence.
const LINE_BREAK: String = "⏎"
## Characters a booklet text is cut into words at, besides spaces: the Prof Tool's
## sentence parser's, plus the typography a story carries. An apostrophe cuts too,
## so "l'ours" is the words "l" and "ours", as the Sentence List stores it.
const SEPARATORS: String = "'’!()[]{};:\"\\,<>./?@#$%^&*_~«»…–—|"

## A chapter of a booklet and everything listed in it.
class Chapter:
	var id: int = -1
	var lesson_id: int = 0
	var lesson_nb: int = 0
	var position: int = 0
	var booklet: int = 1
	var title: String = ""
	## -1 for none: the chapter has no page in the teacher's booklet.
	var image_gp_id: int = -1
	var grey_silent: bool = false
	## Column of SETTINGS -> its value; a column absent here is NULL, the default.
	var overrides: Dictionary[String, float] = {}
	var gp_ids: Array[int] = []
	## {id: SentenceID, brk: Break}, in order.
	var sentences: Array[Dictionary] = []
	## Part -> Array of {text, text2, header}, in order. A word entry also has
	## base: the Words entry it was picked from, which its text must still hold
	## ("la Lune" for "lune"); not saved, worked out again on loading.
	var entries: Dictionary[int, Array] = {}
	## {title, text}, in order.
	var stories: Array[Dictionary] = []

	func get_entries(part: int) -> Array:
		if not entries.has(part):
			entries[part] = []
		return entries[part]

## A font the booklets may print with instead of a default one: a file of
## Kalulu-Languages' fonts/ folder, named by its path there.
class BookletFont:
	var id: int = -1
	var name: String = ""
	var file: String = ""

## BookletSettings: column -> value, Cursive included.
var settings: Dictionary[String, float] = {}
## BookletFonts, in the order they were added.
var fonts: Array[BookletFont] = []
## FONT_ROLES column -> the font replacing that default one; absent keeps it.
var font_choices: Dictionary[String, BookletFont] = {}
var chapters: Array[Chapter] = []
## True when the pack had no chapter and load_from_database() made the default
## ones, which are not in the pack until they are saved.
var made_default_chapters: bool = false

## Lesson ID -> LessonNb, and LessonNb -> lesson ID.
var lesson_numbers: Dictionary[int, int] = {}
var lesson_ids: Dictionary[int, int] = {}
## GP ID -> {grapheme, phoneme, type, exception, lesson}; lesson is the first
## lesson teaching it, -1 for none.
var gps: Dictionary[int, Dictionary] = {}
## Lowercased text -> lesson the entry becomes readable at, -1 when never
## (no decomposition, or a GP no lesson teaches).
var word_lessons: Dictionary[String, int] = {}
var syllable_lessons: Dictionary[String, int] = {}
## Lowercased word -> its ID in Words.
var word_ids: Dictionary[String, int] = {}
## What the Booklets screen picks from, in the pack's order:
## [{text, lesson, booklet_only, exception}], lesson as in word_lessons.
var word_list: Array[Dictionary] = []
var syllable_list: Array[Dictionary] = []
## Everything the writing page, the tables and the fluency test pick from:
## [{text, kind, lesson, booklet_only, exception}], kind "GP", "syllable",
## "word" or "sentence"; a grapheme once, at its first lesson.
var pack_items: Array[Dictionary] = []
## Sentence ID -> {text, lesson, booklet_only}.
var sentences: Dictionary[int, Dictionary] = {}
## Normalized sentence text -> sentence ID.
var _sentence_ids: Dictionary[String, int] = {}


## Reads everything from the open database.
func load_from_database() -> void:
	var db: SQLite = Database.db
	lesson_numbers.clear()
	lesson_ids.clear()
	db.query("SELECT ID, LessonNb FROM Lessons ORDER BY LessonNb")
	for row: Dictionary in db.query_result:
		lesson_numbers[int(row.ID)] = int(row.LessonNb)
		lesson_ids[int(row.LessonNb)] = int(row.ID)
	refresh_lists()

	fonts.clear()
	var fonts_by_id: Dictionary[int, BookletFont] = {}
	db.query("SELECT ID, Name, File FROM BookletFonts ORDER BY ID")
	for row: Dictionary in db.query_result:
		var font: BookletFont = BookletFont.new()
		font.id = int(row.ID)
		font.name = str(row.Name)
		font.file = str(row.File)
		fonts.append(font)
		fonts_by_id[font.id] = font

	settings.clear()
	font_choices.clear()
	db.query("SELECT * FROM BookletSettings ORDER BY ID LIMIT 1")
	if not db.query_result.is_empty():
		var row: Dictionary = db.query_result[0]
		for column: String in ["Cursive"] + SETTINGS.keys():
			settings[column] = float(row[column])
		for column: String in FONT_ROLES:
			if row[column] != null and fonts_by_id.has(int(row[column])):
				font_choices[column] = fonts_by_id[int(row[column])]

	chapters.clear()
	var by_id: Dictionary[int, Chapter] = {}
	db.query("SELECT * FROM BookletChapters")
	for row: Dictionary in db.query_result:
		var chapter: Chapter = Chapter.new()
		chapter.id = int(row.ID)
		chapter.lesson_id = int(row.LessonID)
		chapter.lesson_nb = lesson_numbers.get(chapter.lesson_id, 0)
		chapter.position = int(row.Position)
		chapter.booklet = int(row.Booklet)
		chapter.title = str(row.Title)
		chapter.image_gp_id = -1 if row.ImageGPID == null else int(row.ImageGPID)
		chapter.grey_silent = int(row.GreySilent) != 0
		for column: String in SETTINGS:
			if row[column] != null:
				chapter.overrides[column] = float(row[column])
		chapters.append(chapter)
		by_id[chapter.id] = chapter
	db.query("SELECT ChapterID, GPID FROM BookletChapterGPs ORDER BY ID")
	for row: Dictionary in db.query_result:
		if by_id.has(int(row.ChapterID)):
			by_id[int(row.ChapterID)].gp_ids.append(int(row.GPID))
	db.query("SELECT ChapterID, SentenceID, Break FROM BookletSentences ORDER BY ChapterID, Position")
	for row: Dictionary in db.query_result:
		if by_id.has(int(row.ChapterID)):
			by_id[int(row.ChapterID)].sentences.append({id = int(row.SentenceID), brk = int(row.Break)})
	db.query("SELECT ChapterID, Part, Text, Text2, Header FROM BookletEntries ORDER BY ChapterID, Part, Position")
	for row: Dictionary in db.query_result:
		if by_id.has(int(row.ChapterID)):
			var entry: Dictionary = {text = str(row.Text), text2 = str(row.Text2), header = int(row.Header) != 0}
			if int(row.Part) == Part.WORDS:
				entry.base = base_word(entry.text)
			elif int(row.Part) in PACK_PICKED_PARTS:
				var left: Dictionary = pick_of(entry.text)
				entry.base = left.base
				entry.kind = left.kind
				if not entry.text2.is_empty():
					var right: Dictionary = pick_of(entry.text2)
					entry.base2 = right.base
					entry.kind2 = right.kind
			by_id[int(row.ChapterID)].get_entries(int(row.Part)).append(entry)
	db.query("SELECT ChapterID, Title, Text FROM BookletStories ORDER BY ChapterID, Position")
	for row: Dictionary in db.query_result:
		if by_id.has(int(row.ChapterID)):
			by_id[int(row.ChapterID)].stories.append({title = str(row.Title), text = str(row.Text)})
	sort_chapters()
	made_default_chapters = chapters.is_empty() and not lesson_ids.is_empty()
	if made_default_chapters:
		add_default_chapters()


## A pack with no chapter starts with one per lesson, in the lessons' order,
## each made as Add chapter makes one, every setting the language's: what
## Kalulu-Booklets prints for such a pack (Kalulu-Languages SCHEMA.md, "The
## reading booklets").
func add_default_chapters() -> void:
	for lesson_nb: int in lesson_ids:
		add_chapter(lesson_ids[lesson_nb])


## Rereads the GPs, words, syllables and sentences, leaving the chapters as they
## are being edited.
func refresh_lists() -> void:
	_load_gps()
	word_lessons = _readable_lessons("Words", "Word", "GPsInWords", "WordID")
	word_ids.clear()
	Database.db.query("SELECT ID, Word FROM Words")
	for row: Dictionary in Database.db.query_result:
		word_ids[str(row.Word).to_lower()] = int(row.ID)
	syllable_lessons = _readable_lessons("Syllables", "Syllable", "GPsInSyllables", "SyllableID")
	word_list = _pickable("Words", "Word", word_lessons)
	syllable_list = _pickable("Syllables", "Syllable", syllable_lessons)
	_load_sentences()
	_load_pack_items()


func _load_pack_items() -> void:
	pack_items.clear()
	var graphemes: Dictionary[String, Dictionary] = {}
	for gp: Dictionary in gps.values():
		var grapheme: String = gp.grapheme
		var lesson: int = gp.lesson
		if not graphemes.has(grapheme):
			graphemes[grapheme] = {text = grapheme, kind = "GP", lesson = lesson, booklet_only = false, exception = gp.exception}
		elif lesson >= 0 and (int(graphemes[grapheme].lesson) < 0 or lesson < int(graphemes[grapheme].lesson)):
			graphemes[grapheme].lesson = lesson
			graphemes[grapheme].exception = gp.exception
	pack_items.append_array(graphemes.values())
	for item: Dictionary in syllable_list:
		pack_items.append({text = item.text, kind = "syllable", lesson = item.lesson, booklet_only = item.booklet_only, exception = item.exception})
	for item: Dictionary in word_list:
		pack_items.append({text = item.text, kind = "word", lesson = item.lesson, booklet_only = item.booklet_only, exception = item.exception})
	for sentence_id: int in sentences:
		var sentence: Dictionary = sentences[sentence_id]
		pack_items.append({text = sentence.text, kind = "sentence", lesson = sentence.lesson, booklet_only = sentence.booklet_only, exception = false})


func _pickable(table: String, column: String, lessons: Dictionary[String, int]) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	Database.db.query("SELECT %s AS Text, Exception, BookletOnly FROM %s ORDER BY ID" % [column, table])
	for row: Dictionary in Database.db.query_result:
		var text: String = str(row.Text)
		list.append({text = text, lesson = lessons.get(text.to_lower(), -1),
				booklet_only = int(row.BookletOnly) != 0, exception = int(row.Exception) != 0})
	return list


## The Words entry a word entry is printed from: the longest of its words the
## Word List has ("lune" in "la Lune"), or "" when it has none.
func base_word(text: String) -> String:
	var base: String = ""
	for word: String in words_of(text):
		if word_ids.has(word) and word.length() > base.length():
			base = word
	return base


## The pack item an entry printed as text was picked from: {base, kind}, base ""
## when it holds none. The item spelled exactly so comes first, in the search's
## order (a grapheme, a syllable, a word, a sentence); then the longest word,
## syllable or sentence the text holds. A grapheme only counts spelled alone:
## inside a text, any letter would match one.
func pick_of(text: String) -> Dictionary:
	var wanted: String = normalize(text)
	for kind: String in ["GP", "syllable", "word", "sentence"]:
		for item: Dictionary in pack_items:
			if item.kind == kind and normalize(item.text) == wanted:
				return {base = item.text, kind = kind}
	var best: Dictionary = {base = "", kind = ""}
	for item: Dictionary in pack_items:
		if item.kind != "GP" and str(item.text).length() > str(best.base).length() and holds(text, item.text, item.kind):
			best = {base = item.text, kind = item.kind}
	return best


## Whether a printed text still holds the pack item it was picked from: a word
## or a syllable as one of its words ("lune" in "la Lune", not in "lunette"), a
## grapheme or a sentence anywhere in it, case and spacing ignored.
static func holds(text: String, base: String, kind: String) -> bool:
	if base.is_empty():
		return false
	if kind == "word" or kind == "syllable":
		var pieces: PackedStringArray = words_of(base)
		if pieces.size() == 1:
			return pieces[0] in words_of(text)
	# On one line: a sentence edited in a one-line box loses its line breaks.
	return normalize(base).replace("\n", " ") in normalize(text).replace("\n", " ")


## Why an entry of a part picked from the pack cannot be saved, or "": each of
## its cells must hold what was picked for it. A table row's right cell may be
## empty.
static func picked_entry_problem(entry: Dictionary) -> String:
	var problems: PackedStringArray = []
	var cells: Array[Array] = [[str(entry.text), str(entry.get("base", "")), str(entry.get("kind", ""))]]
	if not str(entry.text2).is_empty():
		cells.append([str(entry.text2), str(entry.get("base2", "")), str(entry.get("kind2", ""))])
	for cell: Array in cells:
		if str(cell[1]).is_empty():
			problems.append("\"%s\" is not picked from the pack" % cell[0])
		elif not holds(cell[0], cell[1], cell[2]):
			problems.append("the %s \"%s\" is printed as \"%s\", which no longer holds it" % [cell[2], cell[1], cell[0]])
	return "; ".join(problems)


## Adds a sentence to the Sentence List, booklet-only, linked word by word to
## Words as the list links its own. Every word must already be in the Word List:
## a word needs a decomposition someone chose, so none is made up here. Writes
## nothing unless every word is found, and all of it in one transaction.
## A sentence already in the list, or added a moment ago, is not added twice.
## Returns {missing: the words not found, error: why nothing was written, or ""}.
func add_booklet_sentence(text: String) -> Dictionary:
	var result: Dictionary = {missing = PackedStringArray(), error = ""}
	if find_sentence(text) >= 0:
		return result
	# A local array: a PackedStringArray read out of a Dictionary is a copy, so
	# appending to result.missing in place would change nothing.
	var linked: Array[int] = []
	var missing: PackedStringArray = []
	for word: String in words_of(text):
		if word_ids.has(word):
			linked.append(word_ids[word])
		elif not word in missing:
			missing.append(word)
	if not missing.is_empty():
		result.missing = missing
		return result
	if linked.is_empty():
		result.error = "\"%s\" has no word in it" % text.strip_edges()
		return result
	var db: SQLite = Database.db
	if not db.query("BEGIN TRANSACTION"):
		result.error = db.get_error_message()
		return result
	if not db.query_with_bindings('INSERT INTO "Sentences" ("Sentence", "BookletOnly") VALUES (?, 1)', [text.strip_edges()]):
		result.error = _rollback("adding a sentence")
		return result
	var sentence_id: int = db.last_insert_rowid
	for position: int in range(linked.size()):
		if not db.query_with_bindings('INSERT INTO "WordsInSentences" ("SentenceID", "WordID", "Position") VALUES (?, ?, ?)',
				[sentence_id, linked[position], position]):
			result.error = _rollback("linking a sentence to its words")
			return result
	if not db.query("COMMIT"):
		result.error = _rollback("adding a sentence")
		return result
	var lesson: int = 0
	for word_id: int in linked:
		var word_lesson: int = word_lessons.get(_word_text(word_id), -1)
		lesson = -1 if lesson < 0 or word_lesson < 0 else maxi(lesson, word_lesson)
	sentences[sentence_id] = {text = text.strip_edges(), lesson = lesson, booklet_only = true}
	_sentence_ids[normalize(text)] = sentence_id
	return result


func _word_text(word_id: int) -> String:
	for word: String in word_ids:
		if word_ids[word] == word_id:
			return word
	return ""


func _load_gps() -> void:
	gps.clear()
	Database.db.query("SELECT GPs.*, (SELECT MIN(Lessons.LessonNb) FROM GPsInLessons
		INNER JOIN Lessons ON Lessons.ID = GPsInLessons.LessonID
		WHERE GPsInLessons.GPID = GPs.ID) AS FirstLesson FROM GPs ORDER BY GPs.ID")
	for row: Dictionary in Database.db.query_result:
		gps[int(row.ID)] = {
			grapheme = str(row.Grapheme),
			phoneme = str(row.Phoneme),
			type = int(row.Type),
			exception = int(row.Exception) != 0,
			lesson = -1 if row.FirstLesson == null else int(row.FirstLesson),
		}


# Text -> lesson an entry of the table is readable at: the last lesson among the
# first lessons of its GPs, as the game works it out. Lowercased here rather than
# in SQL, whose lower() leaves accented letters alone.
func _readable_lessons(table: String, column: String, relation: String, key: String) -> Dictionary[String, int]:
	var lessons: Dictionary[String, int] = {}
	Database.db.query("SELECT %s.%s AS Text, %s.GPID AS GPID FROM %s LEFT JOIN %s ON %s.%s = %s.ID" % [
			table, column, relation, table, relation, relation, key, table])
	for row: Dictionary in Database.db.query_result:
		var text: String = str(row.Text).to_lower()
		var lesson: int = -1
		if row.GPID != null and gps.has(int(row.GPID)):
			lesson = int(gps[int(row.GPID)].lesson)
		if lesson < 0:
			lessons[text] = -1
		elif lessons.get(text, 0) >= 0:
			lessons[text] = maxi(lessons.get(text, 0) as int, lesson)
	return lessons


func _load_sentences() -> void:
	sentences.clear()
	_sentence_ids.clear()
	Database.db.query("SELECT ID, Sentence, BookletOnly FROM Sentences")
	for row: Dictionary in Database.db.query_result:
		sentences[int(row.ID)] = {text = str(row.Sentence), lesson = -1, booklet_only = int(row.BookletOnly) != 0}
		_sentence_ids[normalize(str(row.Sentence))] = int(row.ID)
	Database.db.query("SELECT WordsInSentences.SentenceID AS SentenceID, Words.Word AS Word FROM WordsInSentences
		INNER JOIN Words ON Words.ID = WordsInSentences.WordID")
	var lessons: Dictionary[int, int] = {}
	for row: Dictionary in Database.db.query_result:
		var sentence_id: int = int(row.SentenceID)
		var lesson: int = word_lessons.get(str(row.Word).to_lower(), -1)
		if lessons.get(sentence_id, 0) < 0:
			continue
		lessons[sentence_id] = -1 if lesson < 0 else maxi(lessons.get(sentence_id, 0) as int, lesson)
	for sentence_id: int in lessons:
		if sentences.has(sentence_id):
			sentences[sentence_id].lesson = lessons[sentence_id]


## Sentence text as the Booklets screen matches it: spaces collapsed and trimmed,
## case ignored.
static func normalize(text: String) -> String:
	var lines: PackedStringArray = []
	for line: String in text.strip_edges().split("\n"):
		lines.append(" ".join(line.split(" ", false)))
	return "\n".join(lines).to_lower()


func find_sentence(text: String) -> int:
	return _sentence_ids.get(normalize(text), -1)


## The words of a booklet text, lowercased, in order.
static func words_of(text: String) -> PackedStringArray:
	var cleaned: String = text.to_lower().replace("\n", " ").replace("\t", " ")
	for separator: String in SEPARATORS:
		cleaned = cleaned.replace(separator, " ")
	return cleaned.split(" ", false)


func sort_chapters() -> void:
	for chapter: Chapter in chapters:
		chapter.lesson_nb = lesson_numbers.get(chapter.lesson_id, 0)
	chapters.sort_custom(func(a: Chapter, b: Chapter) -> bool:
		if a.lesson_nb != b.lesson_nb:
			return a.lesson_nb < b.lesson_nb
		return a.position < b.position)
	# Positions 0, 1, 2... within each lesson, whatever happened to them.
	var next: Dictionary[int, int] = {}
	for chapter: Chapter in chapters:
		chapter.position = next.get(chapter.lesson_id, 0)
		next[chapter.lesson_id] = chapter.position + 1


## A new chapter for the lesson, after its other chapters, teaching the lesson's
## GPs, titled after them and pictured with the first one that has an image.
func add_chapter(lesson_id: int) -> Chapter:
	var chapter: Chapter = Chapter.new()
	chapter.lesson_id = lesson_id
	chapter.lesson_nb = lesson_numbers.get(lesson_id, 0)
	chapter.position = 1 << 20
	chapter.booklet = 1
	for other: Chapter in chapters:
		if other.lesson_nb <= chapter.lesson_nb:
			chapter.booklet = maxi(chapter.booklet, other.booklet)
	chapter.gp_ids = lesson_gp_ids(lesson_id)
	chapter.title = title_for(chapter.gp_ids)
	chapter.image_gp_id = first_gp_with_image(chapter.gp_ids)
	chapters.append(chapter)
	sort_chapters()
	return chapter


func lesson_gp_ids(lesson_id: int) -> Array[int]:
	var ids: Array[int] = []
	Database.db.query_with_bindings("SELECT GPID FROM GPsInLessons WHERE LessonID = ? ORDER BY ID", [lesson_id])
	for row: Dictionary in Database.db.query_result:
		if not int(row.GPID) in ids:
			ids.append(int(row.GPID))
	return ids


## A title from GPs: each grapheme once, exceptions and silent letters left out
## unless nothing else is left; a single letter is written with its capital, as
## the booklets do ("L l"). Only a starting point: the booklets often title a
## chapter by contexts ("ci ce cy") rather than graphemes.
func title_for(gp_ids: Array[int]) -> String:
	var kept: Array[int] = []
	for gp_id: int in gp_ids:
		if gps.has(gp_id) and not gps[gp_id].exception and int(gps[gp_id].type) != 0:
			kept.append(gp_id)
	if kept.is_empty():
		kept = gp_ids
	var parts: PackedStringArray = []
	for gp_id: int in kept:
		if not gps.has(gp_id):
			continue
		var grapheme: String = gps[gp_id].grapheme
		var text: String = grapheme
		if grapheme.length() == 1 and grapheme.to_upper() != grapheme:
			text = grapheme.to_upper() + " " + grapheme
		if not text in parts:
			parts.append(text)
	return " ".join(parts)


func first_gp_with_image(gp_ids: Array[int]) -> int:
	for gp_id: int in gp_ids:
		if gps.has(gp_id) and has_image(gp_id):
			return gp_id
	return -1


func has_image(gp_id: int) -> bool:
	return not Database.find_gp_asset_files(gps[gp_id], Database.LOOK_AND_LEARN_IMAGES, Database.IMAGE_EXTENSION).is_empty()


func gp_name(gp_id: int) -> String:
	if not gps.has(gp_id):
		return "?"
	return "%s-%s" % [gps[gp_id].grapheme, gps[gp_id].phoneme]


## The value a chapter prints with for a setting: its own, or the language's.
func value_of(chapter: Chapter, column: String) -> float:
	return chapter.overrides.get(column, settings.get(column, 0.0))


#region Fonts

## A font added from a file: path is where it was picked, which must be inside
## the fonts/ folder of a Kalulu-Languages checkout, the one the generator loads
## fonts from. Returns {font, error}: the new font, or why it was not added.
func add_font(path: String, display_name: String) -> Dictionary:
	var file: String = font_file_in_fonts(path)
	if file.is_empty():
		return {font = null, error = "%s is not inside the fonts folder of a Kalulu-Languages checkout. Put the font there first (with its license in fonts/LICENSE.md), then pick it there." % path}
	if not path.get_extension().to_lower() in FONT_EXTENSIONS:
		return {font = null, error = "%s is not a .ttf or .otf font." % path.get_file()}
	for font: BookletFont in fonts:
		if font.file == file:
			return {font = null, error = "fonts/%s is already added, as \"%s\"." % [file, font.name]}
	var font: BookletFont = BookletFont.new()
	font.file = file
	font.name = unique_font_name(display_name if not display_name.strip_edges().is_empty() else path.get_file().get_basename())
	fonts.append(font)
	return {font = font, error = ""}


## Removes a font; the roles it replaced get their default font back.
func remove_font(font: BookletFont) -> void:
	fonts.erase(font)
	for column: String in font_choices.keys():
		if font_choices[column] == font:
			font_choices.erase(column)


## The path of a font file inside the fonts/ folder of the Kalulu-Languages
## checkout it is in ("andika/Andika-Regular.ttf"), or "" when it is in none. A
## checkout is recognized by its SCHEMA.md beside fonts/.
static func font_file_in_fonts(path: String) -> String:
	var parts: PackedStringArray = path.simplify_path().replace("\\", "/").split("/")
	for index: int in range(parts.size() - 2, -1, -1):
		if parts[index] != "fonts":
			continue
		var checkout: String = "/".join(parts.slice(0, index))
		if FileAccess.file_exists(checkout.path_join("SCHEMA.md")):
			return "/".join(parts.slice(index + 1))
	return ""


## name, or name followed by a number when another font already has it.
func unique_font_name(wanted: String, ignored: BookletFont = null) -> String:
	var base: String = wanted.strip_edges()
	var candidate: String = base
	var number: int = 2
	while _font_named(candidate, ignored) != null:
		candidate = "%s %d" % [base, number]
		number += 1
	return candidate


func _font_named(font_name: String, ignored: BookletFont) -> BookletFont:
	for font: BookletFont in fonts:
		if font != ignored and font.name == font_name:
			return font
	return null


## Every character the pack's syllables, words, sentences and chapter titles
## use, once each, in the order first met: what a font must have to print them.
func pack_characters() -> PackedStringArray:
	var seen: Dictionary[String, bool] = {}
	var texts: Array[String] = []
	for item: Dictionary in syllable_list + word_list:
		texts.append(str(item.text))
	for sentence: Dictionary in sentences.values():
		texts.append(str(sentence.text))
	for chapter: Chapter in chapters:
		texts.append(chapter.title)
	for text: String in texts:
		for index: int in range(text.length()):
			var character: String = text[index]
			if character.strip_edges().is_empty() or seen.has(character):
				continue
			seen[character] = true
	return PackedStringArray(seen.keys())

#endregion

#region What a chapter prints that its lesson cannot read

## What would make the booklet tables unreadable (SCHEMA.md rule 8), one line
## each; Save refuses while there is any. Booklets are numbered 1, 2, 3... along
## the chapters, each chapter in the same booklet as the one before or the next;
## a word entry must still hold the word it was picked from, and each writing,
## table and fluency entry must be picked from the pack and still hold it.
func save_errors() -> PackedStringArray:
	sort_chapters()
	var errors: PackedStringArray = []
	var names: Dictionary[String, bool] = {}
	for font: BookletFont in fonts:
		if font.name.strip_edges().is_empty():
			errors.append("The font fonts/%s has no name" % font.file)
		elif names.has(font.name):
			errors.append("Two fonts are called \"%s\"" % font.name)
		names[font.name] = true
	var previous: Chapter = null
	for chapter: Chapter in chapters:
		var allowed: Array[int] = [1]
		if previous != null:
			allowed = [previous.booklet, previous.booklet + 1]
		if not chapter.booklet in allowed:
			errors.append("%s is in booklet %d, but must be in booklet %s" % [
					chapter_name(chapter), chapter.booklet, " or ".join(PackedStringArray(allowed.map(func(number: int) -> String: return str(number))))])
		previous = chapter
		for entry: Dictionary in chapter.get_entries(Part.WORDS):
			var problem: String = word_entry_problem(entry)
			if not problem.is_empty():
				errors.append("%s: %s" % [chapter_name(chapter), problem])
		for part: int in PACK_PICKED_PARTS:
			for entry: Dictionary in chapter.get_entries(part):
				var problem: String = picked_entry_problem(entry)
				if not problem.is_empty():
					errors.append("%s, %s: %s" % [chapter_name(chapter), PART_NAMES[part], problem])
	return errors


## Why a word entry cannot be saved as it is printed, or "": its text must still
## hold the word it was picked from.
static func word_entry_problem(entry: Dictionary) -> String:
	var base: String = entry.get("base", "")
	if base.is_empty() or base in words_of(entry.text):
		return ""
	return "the word \"%s\" is printed as \"%s\", which no longer holds it" % [base, entry.text]


## What the Booklets screen says, as information, when a chapter picks the same
## syllable or word more than once (a word by the one it was picked from): it may
## be meant, and each pick is printed. "" when every pick is different.
func repeat_info(chapter: Chapter, part: int) -> String:
	var counts: Dictionary[String, int] = {}
	for entry: Dictionary in chapter.get_entries(part):
		var key: String = str(entry.get("base", ""))
		if key.is_empty():
			key = str(entry.text).to_lower()
		counts[key] = counts.get(key, 0) + 1
	var repeated: PackedStringArray = []
	for key: String in counts:
		if counts[key] > 1:
			repeated.append("\"%s\" %d times" % [key, counts[key]])
	if repeated.is_empty():
		return ""
	return "Picked more than once: %s. Each pick is printed." % ", ".join(repeated)


## What the Booklets screen says when a chapter's picks are not the count it
## prints, or "" when they are, or when nothing is picked.
func count_warning(chapter: Chapter, part: int) -> String:
	var picked: int = chapter.get_entries(part).size()
	var count: int = int(value_of(chapter, "SyllableCount" if part == Part.SYLLABLES else "WordCount"))
	var kind: String = "syllable" if part == Part.SYLLABLES else "word"
	if picked == 0 or picked == count:
		return ""
	var picks: String = "%d %s%s picked, %d printed" % [picked, kind, "" if picked == 1 else "s", count]
	if picked > count:
		return "%s: the last %d will be left out." % [picks, picked - count]
	return "%s: the other %d will be chosen from the %ss this lesson can read that hold one of the chapter's GPs, booklet-only ones first, then in the pack's order." % [
			picks, count - picked, kind]


func chapter_name(chapter: Chapter) -> String:
	return "Lesson %d, chapter %d" % [chapter.lesson_nb, chapter.position + 1]


## The problems of a chapter, one line each: what it prints that is unknown to
## the pack, or readable only after its lesson. Nothing here blocks saving; the
## validator reports the sentences again (rule 9), the generator the rest.
func problems(chapter: Chapter) -> PackedStringArray:
	var found: PackedStringArray = []
	for part: int in [Part.SYLLABLES, Part.WORDS]:
		var warning: String = count_warning(chapter, part)
		if not warning.is_empty():
			found.append(warning)
	for entry: Dictionary in chapter.get_entries(Part.TABLES):
		if "|" in str(entry.text2):
			found.append("Table row \"%s | %s\": a table has two cells; the second holds all the rest" % [entry.text, entry.text2])
	for gp_id: int in chapter.gp_ids:
		var lesson: int = gps[gp_id].lesson if gps.has(gp_id) else -1
		if lesson < 0 or lesson > chapter.lesson_nb:
			found.append("GP %s is taught %s" % [gp_name(gp_id), "by no lesson" if lesson < 0 else "in lesson %d" % lesson])
	for item: Dictionary in chapter.sentences:
		var sentence: Dictionary = sentences.get(item.id, {})
		if sentence.is_empty():
			continue
		if int(sentence.lesson) < 0:
			found.append("Sentence \"%s\": never readable (a word without decomposition, or a GP no lesson teaches)" % sentence.text)
		elif int(sentence.lesson) > chapter.lesson_nb:
			found.append("Sentence \"%s\": readable from lesson %d" % [sentence.text, sentence.lesson])
	for part: int in [Part.SYLLABLES, Part.WORDS, Part.TABLES]:
		for entry: Dictionary in chapter.get_entries(part):
			for text: String in [entry.text, entry.text2]:
				found.append_array(_text_problems(text, chapter.lesson_nb, part == Part.SYLLABLES))
	for entry: Dictionary in chapter.get_entries(Part.WRITING):
		if not _is_known_grapheme(entry.text):
			found.append_array(_text_problems(entry.text, chapter.lesson_nb, true))
	var printed_before: Dictionary[String, bool] = _printed_before(chapter)
	for entry: Dictionary in chapter.get_entries(Part.FLUENCY):
		var key: String = " ".join(words_of(entry.text))
		if not printed_before.has(key):
			found.append("Fluency \"%s\": not in an earlier chapter's lists" % entry.text)
	for story: Dictionary in chapter.stories:
		var unknown: PackedStringArray = []
		var later: PackedStringArray = []
		var seen: Dictionary[String, bool] = {}
		for word: String in words_of(str(story.title) + " " + str(story.text)):
			if seen.has(word):
				continue
			seen[word] = true
			var lesson: int = word_lessons.get(word, -2)
			if lesson < 0:
				unknown.append(word)
			elif lesson > chapter.lesson_nb:
				later.append("%s (%d)" % [word, lesson])
		if not unknown.is_empty():
			found.append("Story \"%s\": not studied: %s" % [story.title, ", ".join(unknown)])
		if not later.is_empty():
			found.append("Story \"%s\": taught later: %s" % [story.title, ", ".join(later)])
	return found


func _text_problems(text: String, lesson_nb: int, syllables_too: bool) -> PackedStringArray:
	var found: PackedStringArray = []
	for word: String in words_of(text):
		var lesson: int = word_lessons.get(word, -2)
		if lesson == -2 and syllables_too:
			lesson = syllable_lessons.get(word, -2)
		if lesson == -2:
			found.append("\"%s\": %s is in no list of the pack" % [text, word])
		elif lesson == -1:
			found.append("\"%s\": %s is never readable (no decomposition, or a GP no lesson teaches)" % [text, word])
		elif lesson > lesson_nb:
			found.append("\"%s\": %s is readable from lesson %d" % [text, word, lesson])
	return found


func _is_known_grapheme(text: String) -> bool:
	for gp: Dictionary in gps.values():
		if str(gp.grapheme).to_lower() == text.to_lower():
			return true
	return false


# What the chapters before this one list by hand, word for word.
func _printed_before(chapter: Chapter) -> Dictionary[String, bool]:
	var printed: Dictionary[String, bool] = {}
	for other: Chapter in chapters:
		if other == chapter:
			break
		for part: int in [Part.SYLLABLES, Part.WORDS, Part.WRITING]:
			for entry: Dictionary in other.get_entries(part):
				printed[" ".join(words_of(entry.text))] = true
				for word: String in words_of(entry.text):
					printed[word] = true
	return printed

#endregion

#region Saving

## Writes everything back in one transaction. Chapters keep their IDs; their
## lists are rewritten. Returns an empty string, or the error. Refuses what
## save_errors() reports.
func save_to_database() -> String:
	var errors: PackedStringArray = save_errors()
	if not errors.is_empty():
		return "Not saved: " + "; ".join(errors)
	var new_chapters: Array[Chapter] = []
	for chapter: Chapter in chapters:
		if chapter.id < 0:
			new_chapters.append(chapter)
	var new_fonts: Array[BookletFont] = []
	for font: BookletFont in fonts:
		if font.id < 0:
			new_fonts.append(font)
	var error: String = _save_all()
	if not error.is_empty():
		# Rolled back, so the IDs the new chapters and fonts were given no longer
		# exist and the next insert may be given them again: they are new still.
		for chapter: Chapter in new_chapters:
			chapter.id = -1
		for font: BookletFont in new_fonts:
			font.id = -1
	return error


func _save_all() -> String:
	sort_chapters()
	var db: SQLite = Database.db
	var steps: Array[Array] = []
	var settings_columns: Array = ["Cursive"] + SETTINGS.keys()
	var assignments: PackedStringArray = []
	var values: Array = []
	for column: String in settings_columns:
		assignments.append('"%s" = ?' % column)
		values.append(_column_value(column, settings.get(column, 0.0)))
	# The font columns come after the fonts are saved, once new ones have an ID.
	var font_assignments: PackedStringArray = []
	for column: String in FONT_ROLES:
		font_assignments.append('"%s" = ?' % column)

	var kept_ids: PackedStringArray = []
	for chapter: Chapter in chapters:
		if chapter.id >= 0:
			kept_ids.append(str(chapter.id))
	steps.append(['DELETE FROM "BookletChapters" WHERE ID NOT IN (%s)' % ", ".join(kept_ids), []])

	if not db.query("BEGIN TRANSACTION"):
		return db.get_error_message()
	var font_error: String = _save_fonts()
	if not font_error.is_empty():
		return font_error
	var font_values: Array = []
	for column: String in FONT_ROLES:
		font_values.append(font_choices[column].id if font_choices.has(column) and font_choices[column] in fonts else null)
	steps.push_front(['UPDATE "BookletSettings" SET %s' % ", ".join(assignments + font_assignments), values + font_values])
	for step: Array in steps:
		if not db.query_with_bindings(step[0] as String, step[1] as Array):
			return _rollback("saving the booklet settings")
	for chapter: Chapter in chapters:
		var error: String = _save_chapter(chapter)
		if not error.is_empty():
			return error
	if not db.query("COMMIT"):
		return _rollback("committing")
	return ""


## BookletFonts as listed: removed fonts deleted (ON DELETE SET NULL frees the
## roles they replaced), kept ones renamed, new ones inserted and given their ID.
## Kept fonts first take a name and a file no other row can have, so that two
## swapping names never meet the UNIQUE constraints half-way.
func _save_fonts() -> String:
	var db: SQLite = Database.db
	var kept_ids: PackedStringArray = []
	for font: BookletFont in fonts:
		if font.id >= 0:
			kept_ids.append(str(font.id))
	if not db.query('DELETE FROM "BookletFonts" WHERE ID NOT IN (%s)' % ", ".join(kept_ids)):
		return _rollback("removing fonts")
	if not db.query("UPDATE \"BookletFonts\" SET Name = char(1) || ID, File = char(1) || ID"):
		return _rollback("renaming fonts")
	for font: BookletFont in fonts:
		if font.id >= 0:
			if not db.query_with_bindings('UPDATE "BookletFonts" SET Name = ?, File = ? WHERE ID = ?', [font.name, font.file, font.id]):
				return _rollback("saving a font")
		else:
			if not db.query_with_bindings('INSERT INTO "BookletFonts" (Name, File) VALUES (?, ?)', [font.name, font.file]):
				return _rollback("adding a font")
			font.id = db.last_insert_rowid
	return ""


func _save_chapter(chapter: Chapter) -> String:
	var db: SQLite = Database.db
	var columns: Array = ["LessonID", "Position", "Booklet", "Title", "ImageGPID", "GreySilent"] + SETTINGS.keys()
	var values: Array = [chapter.lesson_id, chapter.position, chapter.booklet, chapter.title,
			null if chapter.image_gp_id < 0 else chapter.image_gp_id, int(chapter.grey_silent)]
	for column: String in SETTINGS:
		values.append(_column_value(column, chapter.overrides[column]) if chapter.overrides.has(column) else null)
	if chapter.id < 0:
		var placeholders: PackedStringArray = []
		for _column: String in columns:
			placeholders.append("?")
		if not db.query_with_bindings('INSERT INTO "BookletChapters" (%s) VALUES (%s)' % [
				", ".join(PackedStringArray(columns)), ", ".join(placeholders)], values):
			return _rollback("adding a chapter")
		chapter.id = db.last_insert_rowid
	else:
		var assignments: PackedStringArray = []
		for column: String in columns:
			assignments.append('"%s" = ?' % column)
		if not db.query_with_bindings('UPDATE "BookletChapters" SET %s WHERE ID = ?' % ", ".join(assignments), values + [chapter.id]):
			return _rollback("saving a chapter")
	for table: String in ["BookletChapterGPs", "BookletSentences", "BookletEntries", "BookletStories"]:
		if not db.query_with_bindings('DELETE FROM "%s" WHERE ChapterID = ?' % table, [chapter.id]):
			return _rollback("clearing a chapter's lists")
	var saved_gps: Array[int] = []
	for gp_id: int in chapter.gp_ids:
		if gp_id in saved_gps:
			continue # each (chapter, GP) pair once: the table is UNIQUE on it
		saved_gps.append(gp_id)
		if not db.query_with_bindings('INSERT INTO "BookletChapterGPs" (ChapterID, GPID) VALUES (?, ?)', [chapter.id, gp_id]):
			return _rollback("saving a chapter's GPs")
	for index: int in range(chapter.sentences.size()):
		var item: Dictionary = chapter.sentences[index]
		if not db.query_with_bindings('INSERT INTO "BookletSentences" (ChapterID, SentenceID, Position, Break) VALUES (?, ?, ?, ?)',
				[chapter.id, item.id, index, Break.NEW_PARAGRAPH if index == 0 else int(item.brk)]):
			return _rollback("saving a chapter's sentences")
	for part: int in chapter.entries:
		var entries: Array = chapter.entries[part]
		for index: int in range(entries.size()):
			var entry: Dictionary = entries[index]
			if not db.query_with_bindings('INSERT INTO "BookletEntries" (ChapterID, Part, Position, Text, Text2, Header) VALUES (?, ?, ?, ?, ?, ?)',
					[chapter.id, part, index, entry.text, entry.text2, int(entry.header and part == Part.TABLES)]):
				return _rollback("saving a chapter's entries")
	for index: int in range(chapter.stories.size()):
		var story: Dictionary = chapter.stories[index]
		if not db.query_with_bindings('INSERT INTO "BookletStories" (ChapterID, Position, Title, Text) VALUES (?, ?, ?, ?)',
				[chapter.id, index, story.title, story.text]):
			return _rollback("saving a chapter's stories")
	return ""


static func _column_value(column: String, value: float) -> Variant:
	if column == "Cursive" or not SETTINGS[column][3]:
		return int(value)
	return value


func _rollback(what: String) -> String:
	var message: String = "Could not save the booklets (%s): %s" % [what, Database.db.get_error_message()]
	Database.db.query("ROLLBACK")
	Log.error("BookletData: " + message)
	return message

#endregion
