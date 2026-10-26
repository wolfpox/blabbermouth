@tool
@icon("res://addons/blabbermouth/icon.svg")
class_name BlabberVocabulary
extends Resource
## Words and phrases that are spoken with real recordings.
##
## Give a voice a vocabulary and every time a line uses one of its words,
## the character says it with one of the word's recordings ("takes")
## instead of the synth voice or the sampled syllables. The take still
## follows the line: the character's pitch, size and speed, the sentence
## melody, and effects like shout, whisper, shiver, wave or slow.
## [codeblock]
## var vocab := BlabberVocabulary.new()
## vocab.add_take("hello", recorded_samples, 48000)
## var voice := BlabberVoice.preset("goblin")
## voice.vocabulary = vocab
## $Blabbermouth.speak("Hello, stranger!", voice)   # "Hello" is the recording
## [/codeblock]
## One vocabulary can be shared by many voices, and each says the words in
## its own pitch and size. Save it as a .blab file with write() (or
## BlabberVoiceFile, inside a voice); with the plugin enabled a vocabulary
## .blab in your project imports as a BlabberVocabulary.

const FORMAT := 1 ## Bumped when the layout changes in a way old versions can't read.
const MAX_WORDS := 2000
const MAX_TAKES := 8 ## Per word.
const MAX_PHRASE := 4 ## Longest phrase, in words.
const MAX_TEXT := 80 ## Longest word or phrase, in letters.

@export var words: Array[BlabberWord] = []
## On: each take moves to the speaker's pitch, throat size and speed (and
## gets their rasp, growl and so on), so one recording fits any character.
## Off: takes keep the recorded voice, and only the line's own changes
## (effects, tags, melody) apply.
@export var fit_to_voice := true


## The name a word is looked up by: lowercase, punctuation removed,
## single spaces between words. "Thank you!" -> "thank you".
static func key_of(text: String) -> String:
	var parts: PackedStringArray = []
	var cur := ""
	for c in text.to_lower().replace("’", "'"):
		if BlabberParser._is_word_char(c):
			cur += c
		elif cur != "":
			parts.append(cur)
			cur = ""
	if cur != "":
		parts.append(cur)
	return " ".join(parts)


## The word with this text (any case or punctuation), or null.
func find(text: String) -> BlabberWord:
	var k := key_of(text)
	if k == "":
		return null
	for w in words:
		if w and w.key == k:
			return w
	return null


## The word with this text, added if it isn't there yet. Null if the text
## has no letters, is too long, or the vocabulary is full.
func add_word(text: String) -> BlabberWord:
	var w := find(text)
	if w:
		return w
	var k := key_of(text)
	if k == "" or k.length() > MAX_TEXT or k.count(" ") >= MAX_PHRASE or words.size() >= MAX_WORDS:
		return null
	w = BlabberWord.create(text.strip_edges())
	words.append(w)
	emit_changed()
	return w


## Adds a recording of a word (adding the word if needed). Returns the new
## take, or null if nothing could be heard in it, the word can't be added,
## or it already has MAX_TAKES takes.
func add_take(text: String, samples: PackedFloat32Array, rate: int) -> BlabberClip:
	var clip := BlabberClip.from_samples(samples, rate)
	if clip.audio.is_empty():
		return null
	return clip if add_clip(text, clip) else null


## Adds an existing take to a word (adding the word if needed). False if it can't.
func add_clip(text: String, clip: BlabberClip) -> bool:
	var w := add_word(text)
	if w == null or clip == null or w.takes.size() >= MAX_TAKES:
		return false
	w.takes.append(clip)
	emit_changed()
	return true


func remove_word(text: String) -> void:
	var w := find(text)
	if w:
		words.erase(w)
		emit_changed()


## Words with at least one take, by key.
func lookup() -> Dictionary:
	var out := {}
	for w in words:
		if w == null or w.takes.is_empty():
			continue
		var k := w.key
		if k != "" and not out.has(k):
			out[k] = w
	return out


## A vocabulary with only the words this line uses (sharing their takes).
func only_used_in(text: String) -> BlabberVocabulary:
	var v := BlabberVocabulary.new()
	v.fit_to_voice = fit_to_voice
	var seen := {}
	for m in BlabberParser.recorded_words(text, self):
		if not seen.has(m.key):
			seen[m.key] = true
			v.words.append(m.word)
	return v


# --- Files --------------------------------------------------------------------

## The vocabulary as plain values (for voice, line and vocabulary files).
func to_dict() -> Dictionary:
	var list: Array = []
	for w in words:
		if w == null or w.key == "":
			continue
		var takes: Array = []
		for c in w.takes:
			if c and not c.audio.is_empty():
				takes.append(_clip_to_dict(c))
		list.append({"text": w.text.left(MAX_TEXT), "takes": takes})
	return {"fit_to_voice": fit_to_voice, "words": list}


## Rebuilds a vocabulary from to_dict() values, checking everything.
## Returns {ok, vocabulary, error}.
static func from_dict(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("words")) != TYPE_ARRAY:
		return _fail("The recorded words in this file are damaged.")
	var v := BlabberVocabulary.new()
	if typeof(d.get("fit_to_voice")) == TYPE_BOOL:
		v.fit_to_voice = d.fit_to_voice
	if d.words.size() > MAX_WORDS:
		return _fail("This file has too many recorded words.")
	for e in d.words:
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("text")) != TYPE_STRING or typeof(e.get("takes", [])) != TYPE_ARRAY:
			return _fail("The recorded words in this file are damaged.")
		var text := _clean_text(e.text)
		var w := v.add_word(text)
		if w == null:
			continue # No letters, or too long: skip it.
		for t in e.get("takes", []):
			var clip := _clip_from_dict(t)
			if clip == null:
				return _fail("A recording of “%s” in this file is damaged." % text)
			if w.takes.size() < MAX_TAKES:
				w.takes.append(clip)
	return {"ok": true, "vocabulary": v, "error": ""}


## The file contents for a vocabulary on its own.
func to_bytes(vocab_name := "") -> PackedByteArray:
	var data := {"blabbermouth_vocabulary": FORMAT, "name": BlabberVoiceFile.clean_name(vocab_name if vocab_name != "" else resource_name)}
	data.merge(to_dict())
	return JSON.stringify(data, "\t").to_utf8_buffer()


## Reads a vocabulary file's contents. Returns {ok, vocabulary, error}.
static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	var parsed := BlabberVoiceFile.decode_json(bytes, "vocabulary")
	if not parsed.ok:
		return _fail(parsed.error)
	var data: Dictionary = parsed.data
	var version = data.get("blabbermouth_vocabulary")
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		return _fail("This isn't a Blabbermouth vocabulary file.")
	if int(version) > FORMAT:
		return _fail("This vocabulary was made with a newer version of Blabbermouth.")
	var r := from_dict(data)
	if r.ok:
		r.vocabulary.resource_name = BlabberVoiceFile.clean_name(str(data.get("name", "")))
	return r


## True if file contents are a vocabulary (rather than a voice or a line).
static func is_vocabulary(bytes: PackedByteArray) -> bool:
	var parsed := BlabberVoiceFile.decode_json(bytes, "vocabulary")
	return parsed.ok and parsed.data.has("blabbermouth_vocabulary")


func write(path: String, vocab_name := "") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes(vocab_name))
	var err := f.get_error()
	f.close()
	return err


## Reads a vocabulary file. Returns {ok, vocabulary, error}.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File not found: " + path.get_file())
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("Could not open %s (%s)." % [path.get_file(), error_string(FileAccess.get_open_error())])
	if f.get_length() > BlabberVoiceFile.MAX_BYTES:
		return _fail("%s is too big to be a vocabulary file." % path.get_file())
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return from_bytes(bytes)


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "vocabulary": null, "error": msg}


## Text from a file, safe to show: no control characters, not too long.
static func _clean_text(text: String) -> String:
	var out := ""
	for c in text:
		if c.unicode_at(0) >= 32:
			out += c
	return out.strip_edges().left(MAX_TEXT)


static func _clip_to_dict(c: BlabberClip) -> Dictionary:
	var pcm := PackedByteArray()
	pcm.resize(c.audio.size() * 2)
	for i in c.audio.size():
		pcm.encode_s16(i * 2, int(clampf(c.audio[i], -1.0, 1.0) * 32767.0))
	var track: Array = []
	for p in c.pitch_track:
		track.append(roundi(p))
	return {
		"rate": c.sample_rate,
		"pitch": snappedf(c.pitch, 0.01),
		"track": track, # Hz every 10 ms, 0 = no pitch
		"audio": Marshalls.raw_to_base64(pcm), # 16-bit little-endian mono
	}


static func _clip_from_dict(d) -> BlabberClip:
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("audio")) != TYPE_STRING:
		return null
	var rate = d.get("rate")
	if typeof(rate) != TYPE_FLOAT and typeof(rate) != TYPE_INT:
		return null
	var sr := int(rate)
	if sr < 8000 or sr > 96000:
		return null
	var pcm := Marshalls.base64_to_raw(d.audio)
	var n := pcm.size() / 2
	if n == 0 or n > int((BlabberClip.MAX_SECONDS + 1.0) * sr):
		return null
	var audio := PackedFloat32Array()
	audio.resize(n)
	for i in n:
		audio[i] = pcm.decode_s16(i * 2) / 32768.0
	var c := BlabberClip.new()
	if sr != BlabberClip.RATE:
		c.audio = BlabberSampleBank.resample(audio, sr, BlabberClip.RATE)
		c.analyze()
		return c
	c.audio = audio
	var track = d.get("track")
	var frames := ceili(n / float(BlabberClip.FRAME))
	var p = d.get("pitch", 0.0)
	if typeof(track) != TYPE_ARRAY or track.size() != frames or (typeof(p) != TYPE_FLOAT and typeof(p) != TYPE_INT):
		c.analyze() # Missing or wrong: measure it again.
		return c
	var t := PackedFloat32Array()
	t.resize(frames)
	for i in frames:
		var v = track[i]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return null
		t[i] = clampf(float(v), 0.0, 2000.0)
	c.pitch_track = t
	c.pitch = clampf(float(p), 0.0, 2000.0)
	return c
