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

## BookletSentences.Break values: what comes before a sentence.
enum Break { SAME_LINE = 0, NEW_LINE = 1, NEW_PARAGRAPH = 2 }

## The settings a chapter can override, in the order the screen shows them:
## column -> [label, lowest, highest (-1 for none), is_real].
const SETTINGS: Dictionary[String, Array] = {
	"SyllableCount": ["Syllables printed", 0, -1, false],
	"SyllableColumns": ["Syllable columns", 1, -1, false],
	"WordCount": ["Words chosen automatically", 0, -1, false],
	"WordColumns": ["Word columns", 1, -1, false],
	"UppercaseProportion": ["Share in capitals (0-1)", 0, 1, true],
	"SentenceFont": ["Sentence font", 0, 2, false],
	"SentenceFirstFont": ["First paragraph's font", 1, 2, false],
	"SentencePages": ["Sentence pages (0 = all)", 0, -1, false],
	"WritingModels": ["Writing: black copies", 0, -1, false],
	"WritingTracings": ["Writing: grey copies to trace", 0, -1, false],
}
const SENTENCE_FONTS: PackedStringArray = ["Alternating", "Script only", "Cursive only"]
const FIRST_FONTS: PackedStringArray = ["", "Script", "Cursive"]

## Characters a booklet text is cut into words at, besides spaces: the Prof Tool's
## sentence parser's, plus the typography a story carries. An apostrophe cuts too,
## so "l'ours" is the words "l" and "ours", as the Sentence List stores it.
const SEPARATORS: String = "'’!()[]{};:\"\\,<>./?@#$%^&*_~«»…–—"

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
	## Part -> Array of {text, text2, header}, in order.
	var entries: Dictionary[int, Array] = {}
	## {title, text}, in order.
	var stories: Array[Dictionary] = []

	func get_entries(part: int) -> Array:
		if not entries.has(part):
			entries[part] = []
		return entries[part]

## BookletSettings: column -> value, Cursive included.
var settings: Dictionary[String, float] = {}
var chapters: Array[Chapter] = []

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

	settings.clear()
	db.query("SELECT * FROM BookletSettings ORDER BY ID LIMIT 1")
	if not db.query_result.is_empty():
		var row: Dictionary = db.query_result[0]
		for column: String in ["Cursive"] + SETTINGS.keys():
			settings[column] = float(row[column])

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
			by_id[int(row.ChapterID)].get_entries(int(row.Part)).append(
					{text = str(row.Text), text2 = str(row.Text2), header = int(row.Header) != 0})
	db.query("SELECT ChapterID, Title, Text FROM BookletStories ORDER BY ChapterID, Position")
	for row: Dictionary in db.query_result:
		if by_id.has(int(row.ChapterID)):
			by_id[int(row.ChapterID)].stories.append({title = str(row.Title), text = str(row.Text)})
	sort_chapters()


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
	_load_sentences()


## Adds a sentence to the Sentence List, booklet-only, linked word by word to
## Words as the list links its own. Every word must already be in the Word List:
## a word needs a decomposition someone chose, so none is made up here. Writes
## nothing unless every word is found, and all of it in one transaction.
## Returns the words not found, empty once the sentence is added.
func add_booklet_sentence(text: String) -> PackedStringArray:
	var linked: Array[int] = []
	var missing: PackedStringArray = []
	for word: String in words_of(text):
		if word_ids.has(word):
			linked.append(word_ids[word])
		elif not word in missing:
			missing.append(word)
	if not missing.is_empty() or linked.is_empty():
		return missing
	var db: SQLite = Database.db
	if not db.query("BEGIN TRANSACTION"):
		return missing
	if not db.query_with_bindings('INSERT INTO "Sentences" ("Sentence", "BookletOnly") VALUES (?, 1)', [text.strip_edges()]):
		_rollback("adding a sentence")
		return missing
	var sentence_id: int = db.last_insert_rowid
	for position: int in range(linked.size()):
		if not db.query_with_bindings('INSERT INTO "WordsInSentences" ("SentenceID", "WordID", "Position") VALUES (?, ?, ?)',
				[sentence_id, linked[position], position]):
			_rollback("linking a sentence to its words")
			return missing
	if not db.query("COMMIT"):
		_rollback("adding a sentence")
	return missing


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
	var words: PackedStringArray = text.strip_edges().split(" ", false)
	return " ".join(words).to_lower()


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


#region Sentences as text

## A chapter's sentences as the screen edits them: one line per printed line,
## " | " between sentences sharing a line, an empty line between paragraphs.
func sentences_text(chapter: Chapter) -> String:
	var text: String = ""
	for index: int in range(chapter.sentences.size()):
		var item: Dictionary = chapter.sentences[index]
		if index > 0:
			match int(item.brk):
				Break.SAME_LINE:
					text += " | "
				Break.NEW_LINE:
					text += "\n"
				_:
					text += "\n\n"
		text += sentences[item.id].text if sentences.has(item.id) else "?"
	return text


## Reads sentences_text() back. Returns {sentences: [{id, brk}], missing: [text]}:
## the sentences found in the Sentence List, and the texts that are not in it.
func parse_sentences(text: String) -> Dictionary:
	var found: Array[Dictionary] = []
	var missing: PackedStringArray = []
	var brk: int = Break.NEW_PARAGRAPH
	for line: String in text.split("\n"):
		if line.strip_edges().is_empty():
			brk = Break.NEW_PARAGRAPH
			continue
		for piece: String in line.split("|"):
			if piece.strip_edges().is_empty():
				continue
			var sentence_id: int = find_sentence(piece)
			if sentence_id < 0:
				missing.append(piece.strip_edges())
			else:
				found.append({id = sentence_id, brk = brk})
			brk = Break.SAME_LINE
		brk = Break.NEW_LINE
	return {sentences = found, missing = missing}

#endregion

#region Entries as text

## A part's entries, one per line; a table row as "left | right", a header row
## starting with "*".
static func entries_text(entries: Array) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		var line: String = entry.text
		if not str(entry.text2).is_empty():
			line += " | " + str(entry.text2)
		if entry.header:
			line = "* " + line
		lines.append(line)
	return "\n".join(lines)


static func parse_entries(text: String, part: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for line: String in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		var header: bool = false
		if part == Part.TABLES and stripped.begins_with("*"):
			header = true
			stripped = stripped.trim_prefix("*").strip_edges()
		var text2: String = ""
		if part == Part.TABLES and "|" in stripped:
			text2 = stripped.get_slice("|", 1).strip_edges()
			stripped = stripped.get_slice("|", 0).strip_edges()
		entries.append({text = stripped, text2 = text2, header = header})
	return entries

#endregion

#region What a chapter prints that its lesson cannot read

## The problems of a chapter, one line each: what it prints that is unknown to
## the pack, or readable only after its lesson. Nothing here blocks saving; the
## validator reports the sentences again (rule 9), the generator the rest.
func problems(chapter: Chapter) -> PackedStringArray:
	var found: PackedStringArray = []
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
		for word: String in words_of(str(story.title) + " " + str(story.text)):
			var lesson: int = word_lessons.get(word, -2)
			if lesson == -2 or lesson == -1:
				if not word in unknown:
					unknown.append(word)
			elif lesson > chapter.lesson_nb and not word in later:
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
## lists are rewritten. Returns an empty string, or the error.
func save_to_database() -> String:
	sort_chapters()
	var db: SQLite = Database.db
	var steps: Array[Array] = []
	var settings_columns: Array = ["Cursive"] + SETTINGS.keys()
	var assignments: PackedStringArray = []
	var values: Array = []
	for column: String in settings_columns:
		assignments.append('"%s" = ?' % column)
		values.append(_column_value(column, settings.get(column, 0.0)))
	steps.append(['UPDATE "BookletSettings" SET %s' % ", ".join(assignments), values])

	var kept_ids: PackedStringArray = []
	for chapter: Chapter in chapters:
		if chapter.id >= 0:
			kept_ids.append(str(chapter.id))
	steps.append(['DELETE FROM "BookletChapters" WHERE ID NOT IN (%s)' % ", ".join(kept_ids), []])

	if not db.query("BEGIN TRANSACTION"):
		return db.get_error_message()
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
	for gp_id: int in chapter.gp_ids:
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
