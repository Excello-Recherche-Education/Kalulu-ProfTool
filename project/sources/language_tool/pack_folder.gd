class_name PackFolder
extends RefCounted
## A language pack on disk is a plain folder: language.db beside its media
## (language_sounds/, look_and_learn/, tracing_data/…), the layout
## Kalulu-Languages stores. The Prof Tool opens a pack from its language.db and
## saves it back the same way, so a pack is copied folder to folder, with no
## archive in between.

const DATABASE_FILE_NAME: String = "language.db"


## Copies every file under from_dir into to_dir, keeping the tree and
## overwriting what is already there. Files only to_dir has are left alone:
## to_dir is a folder the user picked, and nothing here deletes in it.
## Hidden files are skipped (DirAccess does not list them), and so are the
## __MACOSX folders Finder leaves behind when it extracts an archive.
## Copying a folder onto itself does nothing.
static func copy(from_dir: String, to_dir: String) -> Error:
	from_dir = ProjectSettings.globalize_path(from_dir).simplify_path()
	to_dir = ProjectSettings.globalize_path(to_dir).simplify_path()
	if from_dir == to_dir:
		return OK
	# A destination inside the source would be listed while it is being filled,
	# and copied into itself without end.
	if to_dir.begins_with(from_dir + "/"):
		Log.error("PackFolder: Cannot copy %s into %s, which is inside it" % [from_dir, to_dir])
		return ERR_INVALID_PARAMETER
	return _copy_recursive(from_dir, to_dir)


static func _copy_recursive(from_dir: String, to_dir: String) -> Error:
	var dir: DirAccess = DirAccess.open(from_dir)
	if dir == null:
		var open_error: Error = DirAccess.get_open_error()
		Log.error("PackFolder: Cannot open directory %s. Error: %s" % [from_dir, error_string(open_error)])
		return open_error
	var error: Error = DirAccess.make_dir_recursive_absolute(to_dir)
	if error != OK:
		Log.error("PackFolder: Cannot create directory %s. Error: %s" % [to_dir, error_string(error)])
		return error
	for folder_name: String in dir.get_directories():
		if folder_name.to_upper() == "__MACOSX":
			continue
		error = _copy_recursive(from_dir.path_join(folder_name), to_dir.path_join(folder_name))
		if error != OK:
			return error
	for file_name: String in dir.get_files():
		error = DirAccess.copy_absolute(from_dir.path_join(file_name), to_dir.path_join(file_name))
		if error != OK:
			Log.error("PackFolder: Cannot copy %s to %s. Error: %s" % [from_dir.path_join(file_name), to_dir, error_string(error)])
			return error
	return OK
