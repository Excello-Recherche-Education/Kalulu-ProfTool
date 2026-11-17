extends SceneTree
## Sets a pack's share in capitals and draws its capitals, without the Prof
## Tool's window: what the Booklets screen's Apply does. Run it through
## tools/apply-capitals.sh, which finds Godot and the project:
##
##     tools/apply-capitals.sh <pack folder or its language.db> <N> <M>
##
## The pack's language.db is first brought to the Prof Tool's schema version,
## as opening it in the Prof Tool would (PackSchema.upgrade()), then the share
## N / M is written to BookletSettings and BookletData.apply_capitals() draws
## round(rows x N / M) entries of each of Syllables, Words and Sentences, in one
## transaction. Every capital set before, by hand or not, is replaced. 0 in 1
## clears them all.
##
## The database is edited in place: run it on the Kalulu-Languages checkout's
## pack, then open a pull request there as for any pack change.
##
## Prints a line starting with "ERROR:" and quits with code 1 on failure.
## Godot's own exit code is not to be trusted: check the last line printed.

# The project's classes are loaded once the main loop runs, not referenced by
# name: a --script script is compiled before the autoloads (Log) that they use
# are registered.
const PACK_SCHEMA_PATH: String = "res://sources/language_tool/pack_schema.gd"
const BOOKLET_DATA_PATH: String = "res://sources/language_tool/booklet_data.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 3 or not arguments[1].is_valid_int() or not arguments[2].is_valid_int():
		_fail("usage: apply_capitals.gd -- <pack folder or language.db> <N> <M>")
		return
	var path: String = arguments[0]
	if DirAccess.dir_exists_absolute(path):
		path = path.path_join("language.db")
	var count: int = int(arguments[1])
	var in_count: int = int(arguments[2])
	var booklet_data: GDScript = load(BOOKLET_DATA_PATH)
	var max_in: int = booklet_data.get_script_constant_map()["CAPITALS_MAX_IN"]
	if in_count < 1 or in_count > max_in or count < 0 or count > in_count:
		_fail("the share must be N in M with 1 <= M <= %d and 0 <= N <= M, not %d in %d" % [max_in, count, in_count])
		return
	if path.get_file() != "language.db" or not FileAccess.file_exists(path):
		_fail("%s is not a pack's language.db" % path)
		return

	var db: SQLite = SQLite.new()
	db.path = path
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		_fail("could not open %s" % path)
		return
	db.query("PRAGMA foreign_keys = ON")
	var pack_schema: GDScript = load(PACK_SCHEMA_PATH)
	db.query("PRAGMA user_version")
	var before: int = int(db.query_result[0].user_version)
	var error: String = pack_schema.upgrade(db)
	if not error.is_empty():
		db.close_db()
		_fail(error)
		return
	if before != int(pack_schema.VERSION):
		print("Upgraded %s from schema version %d to %d." % [path, before, int(pack_schema.VERSION)])

	error = booklet_data.apply_capitals(db, float(count) / in_count)
	if not error.is_empty():
		db.close_db()
		_fail(error)
		return
	var stored: float = booklet_data.capitals_share(db)
	var fraction: Vector2i = booklet_data.capitals_fraction(stored)
	print("Share in capitals: %d in %d (stored %s)." % [fraction.x, fraction.y, str(stored)])
	var counts: Dictionary = booklet_data.capitals_counts(db)
	for table: String in counts:
		print("%s: %d of %d in capitals." % [table, counts[table][0], counts[table][1]])
	db.close_db()
	print("Done.")
	quit(0)


func _fail(message: String) -> void:
	printerr("ERROR: " + message)
	quit(1)
