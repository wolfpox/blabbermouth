@tool
class_name BlabberVoiceFile
extends RefCounted
## Saves and loads voices as .blab files, for sharing and moving between devices.
## (A .blab file can also hold a whole line of dialogue: see BlabberLineFile.)
##
## A .blab file is plain JSON text: the voice settings, plus the recording
## (as 16-bit audio in base64) when the voice has one, and its vocabulary
## (recorded words) when it has one. Unlike .tres and .res
## files it can't contain code, so it is safe to open files other people made.
## [codeblock]
## BlabberVoiceFile.write(voice, "user://goblin.blab", "Grumpy goblin")
## var result := BlabberVoiceFile.read("user://goblin.blab")
## if result.ok:
##     $Blabbermouth.voice = result.voice
## [/codeblock]

const EXTENSION := "blab"
const FORMAT := 1 ## Bumped when the layout changes in a way old versions can't read.
const MAX_BYTES := 32 * 1024 * 1024
const MAX_NAME := 60
const MAX_TEXT := 400 ## Longest onsets / vowels / codas string.
const SKIP := ["sample_bank"]


## Writes a voice to a file. Returns OK or an error code.
static func write(voice: BlabberVoice, path: String, voice_name := "") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes(voice, voice_name))
	var err := f.get_error()
	f.close()
	return err


## Reads a voice file. Returns {ok, voice, name, error}.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File not found: " + path.get_file())
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("Could not open %s (%s)." % [path.get_file(), error_string(FileAccess.get_open_error())])
	if f.get_length() > MAX_BYTES:
		return _fail("%s is too big to be a voice file." % path.get_file())
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return from_bytes(bytes, path.get_file().get_basename())


## The file contents for a voice, e.g. to download it in a web export.
static func to_bytes(voice: BlabberVoice, voice_name := "") -> PackedByteArray:
	var data := {
		"blabbermouth_voice": FORMAT,
		"name": clean_name(voice_name if voice_name != "" else voice.resource_name),
	}
	data.merge(voice_to_dict(voice))
	return JSON.stringify(data, "\t").to_utf8_buffer()


## Reads a voice from file contents. Returns {ok, voice, name, error}.
## fallback_name is used when the file has no name inside.
## A line file (see BlabberLineFile) gives its speaker's voice.
static func from_bytes(bytes: PackedByteArray, fallback_name := "") -> Dictionary:
	var parsed := decode_json(bytes, "voice")
	if not parsed.ok:
		return _fail(parsed.error)
	var data: Dictionary = parsed.data
	if data.has("blabbermouth_vocabulary"):
		return _fail("This is a vocabulary file, not a voice.")
	if data.has("blabbermouth_line"):
		var line_version = data.blabbermouth_line
		if not _is_num(line_version) or typeof(data.get("speaker")) != TYPE_DICTIONARY:
			return _fail("This line file is damaged.")
		if int(line_version) > BlabberLineFile.FORMAT:
			return _fail("This line was made with a newer version of Blabbermouth.")
		data = data.speaker
	else:
		var version = data.get("blabbermouth_voice")
		if not _is_num(version):
			return _fail("This isn't a Blabbermouth voice file.")
		if int(version) > FORMAT:
			return _fail("This voice was made with a newer version of Blabbermouth.")
	var r := voice_from_dict(data)
	if not r.ok:
		return r
	var voice: BlabberVoice = r.voice
	var voice_name := clean_name(str(data.get("name", "")))
	if voice_name == "":
		voice_name = clean_name(fallback_name)
	voice.resource_name = voice_name
	return {"ok": true, "voice": voice, "name": voice_name, "error": ""}


## A voice as plain values: {"voice": settings, "samples": recording,
## "vocabulary": recorded words}. "samples" and "vocabulary" are left out
## when the voice has none. With only_words_in (a line's text), the
## vocabulary keeps just the words that line uses.
static func voice_to_dict(voice: BlabberVoice, only_words_in = null) -> Dictionary:
	var d := {"voice": settings_of(voice)}
	var bank := voice.sample_bank
	if bank != null and bank.slice_count() > 0:
		d["samples"] = _bank_to_dict(bank)
	var vocab := voice.vocabulary
	if vocab != null and only_words_in is String:
		vocab = vocab.only_used_in(only_words_in)
	if vocab != null and not vocab.lookup().is_empty():
		d["vocabulary"] = vocab.to_dict()
	return d


## Rebuilds a voice from voice_to_dict() values. Returns {ok, voice, error}.
static func voice_from_dict(d: Dictionary) -> Dictionary:
	var voice := BlabberVoice.new()
	var settings = d.get("voice", {})
	if typeof(settings) == TYPE_DICTIONARY:
		apply_settings(voice, settings)
	if d.has("samples"):
		var bank := _bank_from_dict(d.samples)
		if bank == null:
			return _fail("The recording in this file is damaged.")
		voice.sample_bank = bank
	if d.has("vocabulary"):
		var r := BlabberVocabulary.from_dict(d.vocabulary)
		if not r.ok:
			return _fail(r.error)
		voice.vocabulary = r.vocabulary
	return {"ok": true, "voice": voice, "name": "", "error": ""}


## A separate copy of a voice, recording included. The vocabulary is
## shared, since several voices often use the same one.
static func copy_voice(voice: BlabberVoice) -> BlabberVoice:
	var v := BlabberVoice.new()
	apply_settings(v, settings_of(voice))
	if voice.sample_bank:
		v.sample_bank = voice.sample_bank.duplicate()
	v.vocabulary = voice.vocabulary
	v.resource_name = voice.resource_name
	return v


## Checks file contents look like a Blabbermouth JSON file and decodes them.
## Returns {ok, data, error}. what names the file in messages ("voice", "line").
static func decode_json(bytes: PackedByteArray, what := "voice") -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return {"ok": false, "data": {}, "error": "This file is too big to be a %s file." % what}
	# Check it looks like JSON before decoding, so audio or images fail politely.
	var first := 0
	while first < bytes.size() and bytes[first] in [9, 10, 13, 32, 0xEF, 0xBB, 0xBF]:
		first += 1
	if first >= bytes.size() or bytes[first] != 0x7B: # "{"
		return {"ok": false, "data": {}, "error": "This isn't a Blabbermouth %s file." % what}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "This %s file is damaged." % what}
	return {"ok": true, "data": json.data, "error": ""}


## A voice's settings as plain values (no recording).
static func settings_of(voice: BlabberVoice) -> Dictionary:
	var out := {}
	for p in _settings():
		out[p.name] = voice.get(p.name)
	return out


## Copies plain values onto a voice. Unknown names and wrong types are
## ignored, and numbers are kept inside each setting's range.
static func apply_settings(voice: BlabberVoice, values: Dictionary) -> void:
	for p in _settings():
		if not values.has(p.name):
			continue
		var v = values[p.name]
		match p.type:
			TYPE_FLOAT:
				if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
					voice.set(p.name, _clamp_to_hint(float(v), p))
			TYPE_INT:
				if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
					voice.set(p.name, int(_clamp_to_hint(clampf(float(v), -2147483648.0, 2147483647.0), p)))
			TYPE_BOOL:
				if typeof(v) == TYPE_BOOL:
					voice.set(p.name, v)
			TYPE_STRING:
				if typeof(v) == TYPE_STRING:
					voice.set(p.name, (v as String).left(MAX_TEXT))


## A name that is safe to show and to use as a file name.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.unicode_at(0) < 32 or c in "/\\:*?\"<>|":
			out += "_"
		else:
			out += c
	out = out.lstrip(".").strip_edges()
	return out.left(MAX_NAME).strip_edges()


# --- Internals ------------------------------------------------------------------

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "voice": null, "name": "", "error": msg}


## The voice's saved settings: plain numbers, switches and text.
static func _settings() -> Array:
	var out: Array = []
	for p in BlabberVoice.new().get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in SKIP or not p.type in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING]:
			continue
		out.append(p)
	return out


static func _clamp_to_hint(v: float, p: Dictionary) -> float:
	var parts: PackedStringArray = str(p.hint_string).split(",")
	if p.hint == PROPERTY_HINT_RANGE and parts.size() >= 2:
		return clampf(v, parts[0].to_float(), parts[1].to_float())
	if p.hint == PROPERTY_HINT_ENUM:
		return clampf(v, 0.0, parts.size() - 1.0)
	return v


static func _bank_to_dict(bank: BlabberSampleBank) -> Dictionary:
	var pcm := PackedByteArray()
	pcm.resize(bank.audio.size() * 2)
	for i in bank.audio.size():
		pcm.encode_s16(i * 2, int(clampf(bank.audio[i], -1.0, 1.0) * 32767.0))
	var slices: Array = []
	for i in bank.slice_count():
		slices.append([bank.slice_starts[i], bank.slice_ends[i], snappedf(bank.slice_pitch[i], 0.01),
			snappedf(bank.slice_brightness[i], 0.0001), bank.slice_enabled[i]])
	return {
		"rate": bank.sample_rate,
		"sensitivity": bank.sensitivity,
		"base_pitch": snappedf(bank.base_pitch, 0.01),
		"slices": slices, # [start, end, pitch Hz, brightness, enabled]
		"audio": Marshalls.raw_to_base64(pcm), # 16-bit little-endian mono
	}


## Rebuilds a sample bank, checking every value. Returns null if anything is off.
static func _bank_from_dict(d) -> BlabberSampleBank:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var rate = d.get("rate")
	var audio_b64 = d.get("audio")
	var slices = d.get("slices")
	if typeof(rate) != TYPE_FLOAT or typeof(audio_b64) != TYPE_STRING or typeof(slices) != TYPE_ARRAY:
		return null
	var sr := int(rate)
	if sr < 8000 or sr > 96000:
		return null
	var pcm := Marshalls.base64_to_raw(audio_b64)
	var n := pcm.size() / 2
	if n == 0 or n > int(BlabberSampleBank.MAX_SECONDS * sr) + sr:
		return null
	var audio := PackedFloat32Array()
	audio.resize(n)
	for i in n:
		audio[i] = pcm.decode_s16(i * 2) / 32768.0
	var bank := BlabberSampleBank.new()
	bank.audio = audio
	bank.sample_rate = sr
	for s in slices:
		if typeof(s) != TYPE_ARRAY or s.size() < 5:
			return null
		for v in s:
			if typeof(v) != TYPE_FLOAT:
				return null
		var a := int(s[0])
		var b := int(s[1])
		if a < 0 or b <= a or b > n:
			return null
		bank.slice_starts.append(a)
		bank.slice_ends.append(b)
		bank.slice_pitch.append(clampf(s[2], 0.0, 2000.0))
		bank.slice_brightness.append(clampf(s[3], -50.0, 50.0))
		bank.slice_enabled.append(1 if s[4] != 0.0 else 0)
	if bank.slice_count() == 0:
		return null
	var sens = d.get("sensitivity", 0.5)
	bank.sensitivity = clampf(sens, 0.0, 1.0) if typeof(sens) == TYPE_FLOAT else 0.5
	var bp = d.get("base_pitch", 0.0)
	bank.base_pitch = clampf(bp, 0.0, 2000.0) if typeof(bp) == TYPE_FLOAT else 0.0
	return bank
