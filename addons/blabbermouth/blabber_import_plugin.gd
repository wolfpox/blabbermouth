@tool
extends EditorImportPlugin
## Imports .blab files: a voice file becomes a BlabberVoice (drag it onto a
## Blabbermouth node's Voice) and a line file becomes a BlabberLine (give it
## to a BlabberDialogue). Either way it's included in exported games, and
## replacing the .blab file updates everything that uses it.


func _get_importer_name() -> String:
	return "blabbermouth.voice"


func _get_visible_name() -> String:
	return "Blabbermouth Voice or Line"


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
	if BlabberLineFile.is_line(bytes):
		var r := BlabberLineFile.from_bytes(bytes)
		if not r.ok:
			push_error("Blabbermouth: can't import %s: %s" % [source_file, r.error])
			return ERR_PARSE_ERROR
		out = r.line
	else:
		var r := BlabberVoiceFile.from_bytes(bytes)
		if not r.ok:
			push_error("Blabbermouth: can't import %s: %s" % [source_file, r.error])
			return ERR_PARSE_ERROR
		out = r.voice
	# Name it after the file, like other imported assets.
	out.resource_name = source_file.get_file().get_basename()
	return ResourceSaver.save(out, "%s.%s" % [save_path, _get_save_extension()], ResourceSaver.FLAG_COMPRESS)
