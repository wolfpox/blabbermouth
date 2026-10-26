@tool
extends EditorImportPlugin
## Imports .blab files: a voice file becomes a BlabberVoice (drag it onto a
## Blabbermouth node's Voice), a line file becomes a BlabberLine (give it
## to a BlabberDialogue) and a vocabulary file becomes a BlabberVocabulary
## (add it to a voice's Vocabularies). Either way it's included in exported
## games, and replacing the .blab file updates everything that uses it.
## A voice file that links to vocabularies loads them from its own folder,
## so voices that link to the same set share it.


func _get_importer_name() -> String:
	return "blabbermouth.voice"


func _get_visible_name() -> String:
	return "Blabbermouth Voice, Line or Vocabulary"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([BlabberVoiceFile.EXTENSION])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _can_import_threaded() -> bool:
	return false


func _import(source_file: String, save_path: String, _options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var bytes := FileAccess.get_file_as_bytes(source_file)
	var out: Resource
	var stubs: Array = []
	if BlabberVocabulary.is_vocabulary(bytes):
		var r := BlabberVocabulary.from_bytes(bytes)
		if not r.ok:
			push_error("Blabbermouth: can't import %s: %s" % [source_file, r.error])
			return ERR_PARSE_ERROR
		out = r.vocabulary
	elif BlabberLineFile.is_line(bytes):
		var r := BlabberLineFile.from_bytes(bytes)
		if not r.ok:
			push_error("Blabbermouth: can't import %s: %s" % [source_file, r.error])
			return ERR_PARSE_ERROR
		out = r.line
	else:
		var r := BlabberVoiceFile.from_bytes(bytes, "", source_file.get_base_dir())
		if not r.ok:
			push_error("Blabbermouth: can't import %s: %s" % [source_file, r.error])
			return ERR_PARSE_ERROR
		for vs in r.voice.vocabularies:
			if BlabberVoiceFile.is_link(vs):
				push_warning("Blabbermouth: %s uses the recorded words in %s, which isn't in the same folder." % [
					source_file.get_file(), BlabberVoiceFile.link_of(vs)])
		stubs = _refer_to_unimported(bytes, r.voice, source_file.get_base_dir())
		out = r.voice
	# Name it after the file, like other imported assets.
	out.resource_name = source_file.get_file().get_basename()
	var err := ResourceSaver.save(out, "%s.%s" % [save_path, _get_save_extension()], ResourceSaver.FLAG_COMPRESS)
	for stub in stubs:
		stub.resource_path = "" # So nothing else gets the empty stand-in.
	return err


## A linked set that isn't imported yet (it's later in the same import) was
## read from its file instead. Save a reference to its file rather than that
## copy, so voices that link to the same set still share it once loaded.
## Returns the stand-ins used.
func _refer_to_unimported(bytes: PackedByteArray, voice: BlabberVoice, dir: String) -> Array:
	var stubs: Array = []
	var parsed := BlabberVoiceFile.decode_json(bytes, "voice")
	var entries = parsed.data.get("vocabularies") if parsed.ok else null
	if typeof(entries) != TYPE_ARRAY or entries.size() != voice.vocabularies.size():
		return stubs
	for i in entries.size():
		var e = entries[i]
		var vs: BlabberVocabulary = voice.vocabularies[i]
		if typeof(e) != TYPE_DICTIONARY or not e.has("link") or BlabberVoiceFile.is_link(vs) or vs.resource_path != "":
			continue
		var path := dir.path_join(str(e.link))
		if ResourceLoader.has_cached(path):
			continue
		var stub := BlabberVocabulary.new()
		stub.resource_path = path
		voice.vocabularies[i] = stub
		stubs.append(stub)
	return stubs
