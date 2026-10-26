class_name BlabberLibrary
extends RefCounted
## A folder of saved voices (.blab files) on this device.
##
## It lives in user://, the app's own save folder: a normal folder on
## desktop, private app storage on Android, and the browser's storage in web
## exports (kept per browser and per site). Saved voices don't move between
## devices on their own; use BlabberVoiceFile to export and import them.
## [codeblock]
## BlabberLibrary.save(voice, "Grumpy goblin")
## for entry in BlabberLibrary.list():
##     print(entry.name, " ", entry.path)
## var result := BlabberLibrary.open(entry.path)
## [/codeblock]

## Where voices are kept. Change it before use to keep voices elsewhere.
static var folder := "user://voices"

const DEFAULT_NAME := "My voice"
## Files bigger than this hold a recording; settings alone are about 1 KB.
const RECORDING_BYTES := 4096


## Saved voices, newest first: [{name, path, modified, has_recording}].
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension().to_lower() != BlabberVoiceFile.EXTENSION:
			continue
		var path := folder.path_join(f)
		var size := 0
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa:
			size = fa.get_length()
			fa.close()
		out.append({"name": f.get_basename(), "path": path,
			"modified": FileAccess.get_modified_time(path), "has_recording": size > RECORDING_BYTES})
	out.sort_custom(func(a, b): return a.modified > b.modified or (a.modified == b.modified and a.name.naturalnocasecmp_to(b.name) < 0))
	return out


## The file path a voice with this name is saved at.
static func path_for(voice_name: String) -> String:
	var n := BlabberVoiceFile.clean_name(voice_name)
	if n == "":
		n = DEFAULT_NAME
	return folder.path_join(n + "." + BlabberVoiceFile.EXTENSION)


static func has(voice_name: String) -> bool:
	return FileAccess.file_exists(path_for(voice_name))


## The name, or the name with a number added if it is already taken.
static func unique_name(voice_name: String) -> String:
	var base := BlabberVoiceFile.clean_name(voice_name)
	if base == "":
		base = DEFAULT_NAME
	if not has(base):
		return base
	var i := 2
	while has("%s (%d)" % [base, i]):
		i += 1
	return "%s (%d)" % [base, i]


## Saves a voice, replacing any saved voice with the same name.
## link_sets: keep links to the voice's vocabularies instead of copies
## (see BlabberVoiceFile.write()). Returns {ok, path, name, error}.
static func save(voice: BlabberVoice, voice_name: String, link_sets := false) -> Dictionary:
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		return {"ok": false, "path": "", "name": "", "error": "Could not make the voices folder (%s)." % error_string(err)}
	var path := path_for(voice_name)
	var n := path.get_file().get_basename()
	err = BlabberVoiceFile.write(voice, path, n, link_sets)
	if err != OK:
		return {"ok": false, "path": path, "name": n, "error": "Could not save %s (%s)." % [n, error_string(err)]}
	return {"ok": true, "path": path, "name": n, "error": ""}


## Loads a saved voice. Returns {ok, voice, name, error}.
static func open(path: String) -> Dictionary:
	var r := BlabberVoiceFile.read(path)
	if r.ok:
		# The file name is the name shown in the library.
		r.name = path.get_file().get_basename()
		r.voice.resource_name = r.name
	return r


## Gives a saved voice a new name. Returns {ok, path, name, error}.
static func rename(path: String, new_name: String) -> Dictionary:
	var new_path := path_for(new_name)
	var n := new_path.get_file().get_basename()
	if new_path == path:
		return {"ok": true, "path": path, "name": n, "error": ""}
	# A change of capitals only is the same file on Windows and macOS.
	if FileAccess.file_exists(new_path) and new_path.to_lower() != path.to_lower():
		return {"ok": false, "path": path, "name": n, "error": "There is already a voice called %s." % n}
	var err := DirAccess.rename_absolute(path, new_path)
	if err != OK:
		return {"ok": false, "path": path, "name": n, "error": "Could not rename (%s)." % error_string(err)}
	_touch()
	return {"ok": true, "path": new_path, "name": n, "error": ""}


## Deletes a saved voice.
static func remove(path: String) -> Error:
	var err := DirAccess.remove_absolute(path)
	_touch()
	return err


## False when this device or browser won't keep saved files, such as in a
## private browser window. Export voices to keep them in that case.
static func is_persistent() -> bool:
	return OS.is_userfs_persistent()


## Web: asks the browser not to clear saved voices when it runs low on space
## (Safari otherwise may clear sites you haven't visited for a week).
## Does nothing on other platforms.
static func request_persistent_storage() -> void:
	BlabberWeb.persist_storage()


## On the web, Godot copies user:// into the browser's storage after a file is
## written. Removing a file may not count, so write a tiny one to make sure.
static func _touch() -> void:
	var f := FileAccess.open(folder.path_join(".changed"), FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()
