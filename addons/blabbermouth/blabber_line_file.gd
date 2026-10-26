@tool
class_name BlabberLineFile
extends RefCounted
## Saves and loads lines of dialogue as .blab files.
##
## Like a voice file, it is plain JSON and can't contain code. It holds the
## text with its tags and a full copy of the speaker: name, voice (with the
## recording, if any, and the recorded words the line uses) and bubble
## style (with the font, if embedded). Opening
## a line file with BlabberVoiceFile.read() gives the speaker's voice.
## [codeblock]
## BlabberLineFile.write(line, "user://hello_traveler.blab")
## var result := BlabberLineFile.read("user://hello_traveler.blab")
## if result.ok:
##     $Dialogue.say(result.line)
## [/codeblock]
## In a project with the plugin enabled, a .blab line imports as a BlabberLine,
## so load("res://lines/hello_traveler.blab") works too.

const FORMAT := 1 ## Bumped when the layout changes in a way old versions can't read.
const MAX_TEXT := 5000


## Writes a line to a file. Returns OK or an error code.
static func write(line: BlabberLine, path: String, embed_font := true) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes(line, embed_font))
	var err := f.get_error()
	f.close()
	return err


## Reads a line file. Returns {ok, line, error}. load_font false skips an
## embedded font (the bubble then uses the theme's font).
static func read(path: String, load_font := true) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File not found: " + path.get_file())
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("Could not open %s (%s)." % [path.get_file(), error_string(FileAccess.get_open_error())])
	if f.get_length() > BlabberVoiceFile.MAX_BYTES:
		return _fail("%s is too big to be a line file." % path.get_file())
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return from_bytes(bytes, load_font)


## The file contents for a line, e.g. to download it in a web export.
static func to_bytes(line: BlabberLine, embed_font := true) -> PackedByteArray:
	var data := {"blabbermouth_line": FORMAT, "text": line.text.left(MAX_TEXT)}
	if line.speaker:
		data["speaker"] = line.speaker.to_dict(embed_font, line.text.left(MAX_TEXT))
	return JSON.stringify(data, "\t").to_utf8_buffer()


## Reads a line from file contents. Returns {ok, line, error}.
static func from_bytes(bytes: PackedByteArray, load_font := true) -> Dictionary:
	var parsed := BlabberVoiceFile.decode_json(bytes, "line")
	if not parsed.ok:
		return _fail(parsed.error)
	var data: Dictionary = parsed.data
	var version = data.get("blabbermouth_line")
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		if data.has("blabbermouth_voice"):
			return _fail("This is a voice file, not a line.")
		if data.has("blabbermouth_vocabulary"):
			return _fail("This is a vocabulary file, not a line.")
		return _fail("This isn't a Blabbermouth line file.")
	if int(version) > FORMAT:
		return _fail("This line was made with a newer version of Blabbermouth.")
	var line := BlabberLine.new()
	if typeof(data.get("text")) == TYPE_STRING:
		line.text = (data.text as String).left(MAX_TEXT)
	if typeof(data.get("speaker")) == TYPE_DICTIONARY:
		var r := BlabberSpeaker.from_dict(data.speaker, load_font)
		if not r.ok:
			return _fail(r.error)
		line.speaker = r.speaker
	return {"ok": true, "line": line, "error": ""}


## True if file contents are a line rather than a voice.
static func is_line(bytes: PackedByteArray) -> bool:
	var parsed := BlabberVoiceFile.decode_json(bytes, "line")
	return parsed.ok and parsed.data.has("blabbermouth_line")


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "line": null, "error": msg}
