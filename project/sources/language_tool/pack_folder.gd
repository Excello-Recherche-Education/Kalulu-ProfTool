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
## Save copies into a folder the user picked, and must delete nothing there.
## mirror() is the one that deletes, for the local copy.
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


## Makes to_dir the same pack as from_dir: copy() first, then deletes what
## to_dir has and from_dir does not. Only for a folder the Prof Tool owns, the
## local copy under user://: copy() alone kept every file a pack had since
## dropped, and Save then put them back into the pack.
## Nothing is deleted when the copy fails, or when the two are the same folder.
static func mirror(from_dir: String, to_dir: String) -> Error:
	var error: Error = copy(from_dir, to_dir)
	if error != OK:
		return error
	from_dir = ProjectSettings.globalize_path(from_dir).simplify_path()
	to_dir = ProjectSettings.globalize_path(to_dir).simplify_path()
	if from_dir == to_dir:
		return OK
	return _remove_extras(from_dir, to_dir)


## Deletes from to_dir every file and folder from_dir has no counterpart for.
## The counterpart is asked of the filesystem rather than matched by name, so
## two spellings it treats as one file -- é precomposed or not, on macOS -- are
## never mistaken for an extra and deleted.
static func _remove_extras(from_dir: String, to_dir: String) -> Error:
	var dir: DirAccess = DirAccess.open(to_dir)
	if dir == null:
		var open_error: Error = DirAccess.get_open_error()
		Log.error("PackFolder: Cannot open directory %s. Error: %s" % [to_dir, error_string(open_error)])
		return open_error
	var error: Error = OK
	for folder_name: String in dir.get_directories():
		var source_folder: String = from_dir.path_join(folder_name)
		if folder_name.to_upper() == "__MACOSX" or not DirAccess.dir_exists_absolute(source_folder):
			error = _remove_recursive(to_dir.path_join(folder_name))
		else:
			error = _remove_extras(source_folder, to_dir.path_join(folder_name))
		if error != OK:
			return error
	for file_name: String in dir.get_files():
		if FileAccess.file_exists(from_dir.path_join(file_name)):
			continue
		error = DirAccess.remove_absolute(to_dir.path_join(file_name))
		if error != OK:
			Log.error("PackFolder: Cannot delete %s. Error: %s" % [to_dir.path_join(file_name), error_string(error)])
			return error
	return OK


static func _remove_recursive(path: String) -> Error:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		var open_error: Error = DirAccess.get_open_error()
		Log.error("PackFolder: Cannot open directory %s. Error: %s" % [path, error_string(open_error)])
		return open_error
	# Hidden files too, or the folder is not empty and cannot be removed.
	dir.include_hidden = true
	var error: Error = OK
	for folder_name: String in dir.get_directories():
		error = _remove_recursive(path.path_join(folder_name))
		if error != OK:
			return error
	for file_name: String in dir.get_files():
		error = DirAccess.remove_absolute(path.path_join(file_name))
		if error != OK:
			Log.error("PackFolder: Cannot delete %s. Error: %s" % [path.path_join(file_name), error_string(error)])
			return error
	error = DirAccess.remove_absolute(path)
	if error != OK:
		Log.error("PackFolder: Cannot delete %s. Error: %s" % [path, error_string(error)])
	return error


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
