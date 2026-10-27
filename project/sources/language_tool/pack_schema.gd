class_name PackSchema
extends RefCounted
## Brings a language pack's database to the schema this Prof Tool writes, once,
## when the pack is opened.
##
## The schema is version 4 of Kalulu-Languages' SCHEMA.md (exactly
## schema/v4.sql there), and a database says which version it follows in
## PRAGMA user_version. Before this, four screens each patched the parts they
## needed whenever they opened -- the word, syllable and sentence lists added
## Reading / Writing, Lesson Exercises dropped foreign keys and rewrote
## ExerciseTypes -- so a pack's schema depended on which screens someone had
## opened, and none of it said what version the pack was. Now the menu calls
## upgrade() on every pack it opens, and the screens assume the current version.
##
## A pack is upgraded on the copy being edited, so the next save carries it.
## A pack newer than this Prof Tool knows is refused rather than guessed at.

const VERSION: int = 4

const LESSONS_EXERCISES_V1: String = """CREATE TABLE "%s" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"LessonID"	INTEGER NOT NULL,
	"Exercise1"	INTEGER NOT NULL,
	"Exercise2"	INTEGER NOT NULL,
	"Exercise3"	INTEGER NOT NULL,
	PRIMARY KEY("ID" AUTOINCREMENT),
	FOREIGN KEY("LessonID") REFERENCES "Lessons"("ID") ON UPDATE CASCADE ON DELETE CASCADE
)"""
const EXERCISE_TYPES_V1: String = """CREATE TABLE "ExerciseTypes" (
	"ID"	INTEGER PRIMARY KEY ASC AUTOINCREMENT UNIQUE NOT NULL,
	"Type"	TEXT NOT NULL
)"""
## The reading booklets' tables, as in schema/v2.sql.
const BOOKLET_TABLES_V2: Dictionary[String, String] = {
	"BookletSettings": """CREATE TABLE "BookletSettings" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"Cursive"	INTEGER NOT NULL DEFAULT 1,
	"SyllableCount"	INTEGER NOT NULL DEFAULT 12,
	"SyllableColumns"	INTEGER NOT NULL DEFAULT 6,
	"WordCount"	INTEGER NOT NULL DEFAULT 12,
	"WordColumns"	INTEGER NOT NULL DEFAULT 4,
	"UppercaseProportion"	REAL NOT NULL DEFAULT 0,
	"SentenceFont"	INTEGER NOT NULL DEFAULT 0,
	"SentenceFirstFont"	INTEGER NOT NULL DEFAULT 2,
	"SentencePages"	INTEGER NOT NULL DEFAULT 1,
	"WritingModels"	INTEGER NOT NULL DEFAULT 1,
	"WritingTracings"	INTEGER NOT NULL DEFAULT 2,
	PRIMARY KEY("ID" AUTOINCREMENT)
)""",
	"BookletChapters": """CREATE TABLE "BookletChapters" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"LessonID"	INTEGER NOT NULL,
	"Position"	INTEGER NOT NULL,
	"Booklet"	INTEGER NOT NULL DEFAULT 1,
	"Title"	TEXT NOT NULL DEFAULT '',
	"ImageGPID"	INTEGER,
	"GreySilent"	INTEGER NOT NULL DEFAULT 0,
	"SyllableCount"	INTEGER,
	"SyllableColumns"	INTEGER,
	"WordCount"	INTEGER,
	"WordColumns"	INTEGER,
	"UppercaseProportion"	REAL,
	"SentenceFont"	INTEGER,
	"SentenceFirstFont"	INTEGER,
	"SentencePages"	INTEGER,
	"WritingModels"	INTEGER,
	"WritingTracings"	INTEGER,
	PRIMARY KEY("ID" AUTOINCREMENT),
	FOREIGN KEY("LessonID") REFERENCES "Lessons"("ID") ON UPDATE CASCADE ON DELETE RESTRICT,
	FOREIGN KEY("ImageGPID") REFERENCES "GPs"("ID") ON UPDATE CASCADE ON DELETE SET NULL
)""",
	"BookletChapterGPs": """CREATE TABLE "BookletChapterGPs" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"ChapterID"	INTEGER NOT NULL,
	"GPID"	INTEGER NOT NULL,
	PRIMARY KEY("ID" AUTOINCREMENT),
	UNIQUE("ChapterID", "GPID"),
	FOREIGN KEY("ChapterID") REFERENCES "BookletChapters"("ID") ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY("GPID") REFERENCES "GPs"("ID") ON UPDATE CASCADE ON DELETE CASCADE
)""",
	"BookletSentences": """CREATE TABLE "BookletSentences" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"ChapterID"	INTEGER NOT NULL,
	"SentenceID"	INTEGER NOT NULL,
	"Position"	INTEGER NOT NULL,
	"Break"	INTEGER NOT NULL DEFAULT 2,
	PRIMARY KEY("ID" AUTOINCREMENT),
	FOREIGN KEY("ChapterID") REFERENCES "BookletChapters"("ID") ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY("SentenceID") REFERENCES "Sentences"("ID") ON UPDATE CASCADE ON DELETE CASCADE
)""",
	"BookletEntries": """CREATE TABLE "BookletEntries" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"ChapterID"	INTEGER NOT NULL,
	"Part"	INTEGER NOT NULL,
	"Position"	INTEGER NOT NULL,
	"Text"	TEXT NOT NULL,
	"Text2"	TEXT NOT NULL DEFAULT '',
	"Header"	INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY("ID" AUTOINCREMENT),
	FOREIGN KEY("ChapterID") REFERENCES "BookletChapters"("ID") ON UPDATE CASCADE ON DELETE CASCADE
)""",
	"BookletStories": """CREATE TABLE "BookletStories" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"ChapterID"	INTEGER NOT NULL,
	"Position"	INTEGER NOT NULL,
	"Title"	TEXT NOT NULL DEFAULT '',
	"Text"	TEXT NOT NULL DEFAULT '',
	PRIMARY KEY("ID" AUTOINCREMENT),
	FOREIGN KEY("ChapterID") REFERENCES "BookletChapters"("ID") ON UPDATE CASCADE ON DELETE CASCADE
)""",
}
## The booklets' fonts, as in schema/v3.sql: the table, and the BookletSettings
## columns naming the font that replaces each default one.
const BOOKLET_FONTS_V3: String = """CREATE TABLE "BookletFonts" (
	"ID"	INTEGER NOT NULL UNIQUE,
	"Name"	TEXT NOT NULL UNIQUE,
	"File"	TEXT NOT NULL UNIQUE,
	PRIMARY KEY("ID" AUTOINCREMENT)
)"""
const FONT_COLUMNS_V3: PackedStringArray = ["ScriptFontID", "ScriptBoldFontID", "ScriptBlackFontID", "CursiveFontID"]


## Upgrades the open database to VERSION when it is older, and keeps
## ExerciseTypes matching MinigameTypes.NAMES. Returns an empty string when the
## pack can be edited, or a message for the user when it cannot.
static func upgrade(db: SQLite) -> String:
	var version: int = _user_version(db)
	if version > VERSION:
		return "This language pack uses schema version %d, and this Prof Tool only knows up to version %d. Update the Prof Tool before editing it." % [version, VERSION]
	if version < 1:
		var error: String = _to_v1(db)
		if not error.is_empty():
			return error
	if version < 2:
		var error: String = _to_v2(db)
		if not error.is_empty():
			return error
	if version < 3:
		var error: String = _to_v3(db)
		if not error.is_empty():
			return error
	if version < 4:
		var error: String = _to_v4(db)
		if not error.is_empty():
			return error
	if version < VERSION:
		Log.info("PackSchema: upgraded %s from schema version %d to %d" % [db.path, version, VERSION])
	return _reconcile_exercise_types(db)


static func _user_version(db: SQLite) -> int:
	db.query("PRAGMA user_version")
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("user_version", 0))


static func _columns(db: SQLite, table: String) -> Array[String]:
	var names: Array[String] = []
	db.query("PRAGMA table_info('%s')" % table)
	for row: Dictionary in db.query_result:
		names.append(str(row.name))
	return names


static func _table_exists(db: SQLite, table: String) -> bool:
	db.query_with_bindings("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [table])
	return not db.query_result.is_empty()


## Version 0 to 1: the four changes Kalulu-Languages' packs were migrated with
## on 2026-10-16, in one transaction. Each is skipped when already done.
static func _to_v1(db: SQLite) -> String:
	# Rebuilding LessonsExercises drops a table; foreign keys cannot be switched
	# inside a transaction, so they are switched off around it.
	db.query("PRAGMA foreign_keys = OFF")
	var steps: Array[String] = ["BEGIN TRANSACTION"]

	# 1. Reading / Writing, with v1's defaults -- what the screens used to add.
	for table: String in ["Words", "Syllables", "Sentences"]:
		var columns: Array[String] = _columns(db, table)
		if not "Reading" in columns:
			steps.append('ALTER TABLE "%s" ADD COLUMN "Reading" INTEGER DEFAULT 1' % table)
		if not "Writing" in columns:
			steps.append('ALTER TABLE "%s" ADD COLUMN "Writing" INTEGER DEFAULT 0' % table)

	# 2. LessonsExercises without foreign keys on the minigame slots: 0 means
	# "no minigame", which no ExerciseTypes row has. IDs and the AUTOINCREMENT
	# counter are kept as they were, absent included.
	if not _table_exists(db, "LessonsExercises"):
		steps.append(LESSONS_EXERCISES_V1 % "LessonsExercises")
	elif _has_exercise_foreign_keys(db):
		db.query("SELECT seq FROM sqlite_sequence WHERE name = 'LessonsExercises'")
		var counter: Array = db.query_result.duplicate()
		steps.append(LESSONS_EXERCISES_V1 % "LessonsExercises_v1")
		steps.append('INSERT INTO "LessonsExercises_v1" (ID, LessonID, Exercise1, Exercise2, Exercise3) SELECT ID, LessonID, Exercise1, Exercise2, Exercise3 FROM "LessonsExercises"')
		steps.append('DROP TABLE "LessonsExercises"')
		steps.append('ALTER TABLE "LessonsExercises_v1" RENAME TO "LessonsExercises"')
		steps.append("DELETE FROM sqlite_sequence WHERE name = 'LessonsExercises'")
		if not counter.is_empty():
			steps.append("INSERT INTO sqlite_sequence (name, seq) VALUES ('LessonsExercises', %d)" % int(counter[0].seq))

	# 3. ExerciseTypes exists; its rows are matched to the names below.
	if not _table_exists(db, "ExerciseTypes"):
		steps.append(EXERCISE_TYPES_V1)

	for step: String in steps:
		if not db.query(step):
			var message: String = "Could not bring this language pack to schema version 1: %s" % db.get_error_message()
			db.query("ROLLBACK")
			db.query("PRAGMA foreign_keys = ON")
			Log.error("PackSchema: %s (step: %s)" % [message, step.left(80)])
			return message

	# 4. The rows of ExerciseTypes, then the version, still inside the transaction.
	var error: String = _write_exercise_types(db)
	if error.is_empty() and not db.query("PRAGMA user_version = 1"):
		error = db.get_error_message()
	if not error.is_empty():
		db.query("ROLLBACK")
		db.query("PRAGMA foreign_keys = ON")
		Log.error("PackSchema: could not finish the upgrade: %s" % error)
		return "Could not bring this language pack to schema version 1: %s" % error
	if not db.query("COMMIT"):
		error = db.get_error_message()
		db.query("ROLLBACK")
		db.query("PRAGMA foreign_keys = ON")
		Log.error("PackSchema: could not commit the upgrade: %s" % error)
		return "Could not bring this language pack to schema version 1: %s" % error
	db.query("PRAGMA foreign_keys = ON")
	return ""


## Version 1 to 2, for the reading booklets: the BookletOnly flag on Words,
## Syllables and Sentences, at 0 so every entry stays the game's, and the
## Booklet* tables with their one BookletSettings row -- what Kalulu-Languages'
## schema/v1-to-v2.sql does. In one transaction; each part is skipped when
## already there.
static func _to_v2(db: SQLite) -> String:
	var steps: Array[String] = ["BEGIN TRANSACTION"]
	for table: String in ["Words", "Syllables", "Sentences"]:
		if not "BookletOnly" in _columns(db, table):
			steps.append('ALTER TABLE "%s" ADD COLUMN "BookletOnly" INTEGER NOT NULL DEFAULT 0' % table)
	for table: String in BOOKLET_TABLES_V2:
		if not _table_exists(db, table):
			steps.append(BOOKLET_TABLES_V2[table])
	# SentencePages 0, not the column's DEFAULT 1: 0 is the chapter page only,
	# what 1 meant until 2026-10-27 (Kalulu-Languages schema/v1-to-v2.sql).
	steps.append('INSERT INTO "BookletSettings" ("Cursive", "SentencePages") SELECT 1, 0 WHERE NOT EXISTS (SELECT 1 FROM "BookletSettings")')
	steps.append("PRAGMA user_version = 2")
	for step: String in steps:
		if not db.query(step):
			var message: String = "Could not bring this language pack to schema version 2: %s" % db.get_error_message()
			db.query("ROLLBACK")
			Log.error("PackSchema: %s (step: %s)" % [message, step.left(80)])
			return message
	if not db.query("COMMIT"):
		var message: String = "Could not bring this language pack to schema version 2: %s" % db.get_error_message()
		db.query("ROLLBACK")
		Log.error("PackSchema: %s" % message)
		return message
	return ""


## Version 2 to 3, for the booklets' fonts: the empty BookletFonts table and the
## four BookletSettings font columns, NULL so every booklet keeps its default
## fonts -- what Kalulu-Languages' schema/v2-to-v3.sql does. In one transaction;
## each part is skipped when already there.
static func _to_v3(db: SQLite) -> String:
	var steps: Array[String] = ["BEGIN TRANSACTION"]
	if not _table_exists(db, "BookletFonts"):
		steps.append(BOOKLET_FONTS_V3)
	var settings_columns: Array[String] = _columns(db, "BookletSettings")
	for column: String in FONT_COLUMNS_V3:
		if not column in settings_columns:
			steps.append('ALTER TABLE "BookletSettings" ADD COLUMN "%s" INTEGER REFERENCES "BookletFonts"("ID") ON UPDATE CASCADE ON DELETE SET NULL' % column)
	steps.append("PRAGMA user_version = 3")
	for step: String in steps:
		if not db.query(step):
			var message: String = "Could not bring this language pack to schema version 3: %s" % db.get_error_message()
			db.query("ROLLBACK")
			Log.error("PackSchema: %s (step: %s)" % [message, step.left(80)])
			return message
	if not db.query("COMMIT"):
		var message: String = "Could not bring this language pack to schema version 3: %s" % db.get_error_message()
		db.query("ROLLBACK")
		Log.error("PackSchema: %s" % message)
		return message
	return ""


## Version 3 to 4: Words, Syllables and Sentences lose their Writing column,
## which no program read -- what Kalulu-Languages' schema/v3-to-v4.sql does. In
## one transaction; a table already without it is skipped.
static func _to_v4(db: SQLite) -> String:
	var steps: Array[String] = ["BEGIN TRANSACTION"]
	for table: String in ["Words", "Syllables", "Sentences"]:
		if "Writing" in _columns(db, table):
			steps.append('ALTER TABLE "%s" DROP COLUMN "Writing"' % table)
	steps.append("PRAGMA user_version = 4")
	for step: String in steps:
		if not db.query(step):
			var message: String = "Could not bring this language pack to schema version 4: %s" % db.get_error_message()
			db.query("ROLLBACK")
			Log.error("PackSchema: %s (step: %s)" % [message, step.left(80)])
			return message
	if not db.query("COMMIT"):
		var message: String = "Could not bring this language pack to schema version 4: %s" % db.get_error_message()
		db.query("ROLLBACK")
		Log.error("PackSchema: %s" % message)
		return message
	return ""


static func _has_exercise_foreign_keys(db: SQLite) -> bool:
	db.query("PRAGMA foreign_key_list('LessonsExercises')")
	for foreign_key: Dictionary in db.query_result:
		if str(foreign_key.get("from", "")).begins_with("Exercise"):
			return true
	return false


## ExerciseTypes holds MinigameTypes.NAMES, row ID n = NAMES[n - 1], and
## LessonsExercises stores those IDs. Checked on every open, so a renamed
## minigame reaches every pack; writes nothing when the names already match.
static func _reconcile_exercise_types(db: SQLite) -> String:
	var expected: Array = []
	for index: int in MinigameTypes.NAMES.size():
		expected.append({ID = index + 1, Type = MinigameTypes.NAMES[index]})
	db.query("SELECT ID, Type FROM ExerciseTypes ORDER BY ID")
	var stored: Array = []
	for row: Dictionary in db.query_result:
		stored.append({ID = int(row.ID), Type = str(row.Type)})
	if stored == expected:
		return ""
	return _write_exercise_types(db)


## Writes ExerciseTypes to match MinigameTypes.NAMES by ID, which is what makes a
## rename work: matching by name would keep the old row and append the new name
## as an extra one a lesson could be assigned to. A slot pointing past the list
## is freed (0 = no minigame) before its row goes.
##
## Plain queries only: godot-sqlite's insert_row() and update_rows() open and
## commit a transaction of their own, which would commit _to_v1()'s half-way.
static func _write_exercise_types(db: SQLite) -> String:
	for index: int in MinigameTypes.NAMES.size():
		var exercise_id: int = index + 1
		var exercise_name: String = MinigameTypes.NAMES[index]
		db.query("SELECT Type FROM ExerciseTypes WHERE ID = %d" % exercise_id)
		if db.query_result.is_empty():
			if not db.query_with_bindings("INSERT INTO ExerciseTypes (ID, Type) VALUES (?, ?)", [exercise_id, exercise_name]):
				return db.get_error_message()
		elif str(db.query_result[0].Type) != exercise_name:
			Log.info("PackSchema: ExerciseType %d: %s -> %s" % [exercise_id, str(db.query_result[0].Type), exercise_name])
			if not db.query_with_bindings("UPDATE ExerciseTypes SET Type = ? WHERE ID = ?", [exercise_name, exercise_id]):
				return db.get_error_message()
	var last_id: int = MinigameTypes.NAMES.size()
	for column: String in ["Exercise1", "Exercise2", "Exercise3"]:
		db.query("UPDATE LessonsExercises SET %s = 0 WHERE %s > %d" % [column, column, last_id])
	db.query("DELETE FROM ExerciseTypes WHERE ID > %d" % last_id)
	return ""
