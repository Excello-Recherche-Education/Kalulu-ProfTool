class_name PackSchema
extends RefCounted
## Brings a language pack's database to the schema this Prof Tool writes, once,
## when the pack is opened.
##
## The schema is version 1 of Kalulu-Languages' SCHEMA.md (exactly
## schema/v1.sql there), and a database says which version it follows in
## PRAGMA user_version. Before this, four screens each patched the parts they
## needed whenever they opened -- the word, syllable and sentence lists added
## Reading / Writing, Lesson Exercises dropped foreign keys and rewrote
## ExerciseTypes -- so a pack's schema depended on which screens someone had
## opened, and none of it said what version the pack was. Now the menu calls
## upgrade() on every pack it opens, and the screens assume v1.
##
## A pack is upgraded on the copy being edited, so the next export carries v1.
## A pack newer than this Prof Tool knows is refused rather than guessed at.

const VERSION: int = 1

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


## Upgrades the open database to VERSION when it is older, and keeps
## ExerciseTypes matching MinigameTypes.NAMES. Returns an empty string when the
## pack can be edited, or a message for the user when it cannot.
static func upgrade(db: SQLite) -> String:
	var version: int = _user_version(db)
	if version > VERSION:
		return "This language pack uses schema version %d, and this Prof Tool only knows up to version %d. Update the Prof Tool before editing it." % [version, VERSION]
	if version < VERSION:
		var error: String = _to_v1(db)
		if not error.is_empty():
			return error
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
			var message: String = "Could not bring this language pack to schema version %d: %s" % [VERSION, db.get_error_message()]
			db.query("ROLLBACK")
			db.query("PRAGMA foreign_keys = ON")
			Log.error("PackSchema: %s (step: %s)" % [message, step.left(80)])
			return message

	# 4. The rows of ExerciseTypes, then the version, still inside the transaction.
	var error: String = _write_exercise_types(db)
	if error.is_empty() and not db.query("PRAGMA user_version = %d" % VERSION):
		error = db.get_error_message()
	if not error.is_empty():
		db.query("ROLLBACK")
		db.query("PRAGMA foreign_keys = ON")
		Log.error("PackSchema: could not finish the upgrade: %s" % error)
		return "Could not bring this language pack to schema version %d: %s" % [VERSION, error]
	db.query("COMMIT")
	db.query("PRAGMA foreign_keys = ON")
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
