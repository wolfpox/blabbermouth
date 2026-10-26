extends RefCounted
## The demo's characters. Each is a BlabberSpeaker (name, voice, bubble) plus
## what the editor needs around it: the voice preset it started from, a
## recording that's kept even while the synth voice is in use, and whether
## it uses the shared vocabulary (recorded words).

const SAVE_PATH := "user://editor.json"
const FORMAT := 1

## Fonts that ship with the demo. "size" suits each one's look.
const FONTS := {
	"alegreya": {"label": "Alegreya · storybook", "path": "res://demo/fonts/alegreya.ttf", "size": 27},
	"nunito": {"label": "Nunito · soft and round", "path": "res://demo/fonts/nunito.ttf", "size": 26},
	"fredoka": {"label": "Fredoka · bubbly", "path": "res://demo/fonts/fredoka.ttf", "size": 27},
	"patrick_hand": {"label": "Patrick Hand · handwritten", "path": "res://demo/fonts/patrick_hand.ttf", "size": 30},
	"cormorant": {"label": "Cormorant · old book", "path": "res://demo/fonts/cormorant.ttf", "size": 30},
	"bangers": {"label": "Bangers · comic caps", "path": "res://demo/fonts/bangers.ttf", "size": 29},
	"grenze": {"label": "Grenze · gothic", "path": "res://demo/fonts/grenze.ttf", "size": 27},
	"vt323": {"label": "VT323 · terminal", "path": "res://demo/fonts/vt323.ttf", "size": 33},
}
const CORNERS := {"round": 34, "soft": 16, "square": 3}

## The starting cast, from the design mock-up.
## shadow: [color, size, x, y]
const DEFAULTS := [
	{"name": "Aldric", "kind": "man", "font": "alegreya", "fill": "f4ecdd", "ink": "2a1d12", "muted": "6b5a47",
		"line": "4a3423", "lw": 3, "corner": "soft", "shadow": ["00000040", 1, 0, 6], "tag": "4a3423", "tag_ink": "f4ecdd", "words": true},
	{"name": "Mira", "kind": "woman", "font": "nunito", "fill": "ffffff", "ink": "2b1a22", "muted": "7a5a68",
		"line": "b8325f", "lw": 3, "corner": "round", "shadow": ["00000040", 1, 0, 6], "tag": "b8325f", "tag_ink": "ffffff", "words": true},
	{"name": "Pip", "kind": "critter", "font": "fredoka", "fill": "ffe07a", "ink": "2b2210", "muted": "5e4f1f",
		"line": "2b2210", "lw": 4, "corner": "round", "shadow": ["2b2210", 1, 0, 7], "tag": "2b2210", "tag_ink": "ffe07a", "words": false},
	{"name": "Tamsin", "kind": "child", "font": "patrick_hand", "fill": "ddf3fb", "ink": "12313d", "muted": "3f6070",
		"line": "1f6e8c", "lw": 3, "corner": "round", "shadow": ["00000040", 1, 0, 6], "tag": "1f6e8c", "tag_ink": "ffffff", "words": true},
	{"name": "Old Hesk", "kind": "elder", "font": "cormorant", "fill": "edebe4", "ink": "2e2c27", "muted": "6a675e",
		"line": "6e6a5e", "lw": 5, "corner": "soft", "shadow": ["00000040", 1, 0, 6], "tag": "6e6a5e", "tag_ink": "ffffff", "words": true},
	{"name": "Grub", "kind": "goblin", "font": "bangers", "fill": "e3f0cf", "ink": "1f3311", "muted": "4e6a3a",
		"line": "2f4a1a", "lw": 4, "corner": "square", "shadow": ["2f4a1a", 1, 6, 6], "tag": "2f4a1a", "tag_ink": "e3f0cf", "words": false},
	{"name": "The Thing Below", "kind": "monster", "font": "grenze", "fill": "1d1322", "ink": "ebddf5", "muted": "b9a6c8",
		"line": "b07fd6", "lw": 3, "corner": "soft", "shadow": ["b07fd62e", 8, 0, 0], "tag": "b07fd6", "tag_ink": "1d1322", "words": false},
	{"name": "UNIT-7", "kind": "robot", "font": "vt323", "fill": "0b1a1f", "ink": "5ce1e6", "muted": "3fa3a8",
		"line": "5ce1e6", "lw": 2, "corner": "square", "shadow": ["2b6e72aa", 5, 0, 0], "tag": "5ce1e6", "tag_ink": "0b1a1f", "words": true},
]

## Lines to try, each with the character who says it best.
const SAMPLES := [
	["Aldric", "Hello there, [wave]traveler![/wave] Have you seen my [swell]little lantern[/swell]? It was right here...[pause=0.5] [whisper][speed=0.6]I swear.[/speed][/whisper]"],
	["Tamsin", "[shiver]W-what was that noise?[/shiver][pause=0.4] Probably nothing. [droop]Probably.[/droop]"],
	["Grub", "[shout]GET OUT OF MY SWAMP![/shout] [droop]...unless you brought snacks.[/droop]"],
	["Pip", "[whisper]Psst. The king is a frog.[/whisper] [speed=1.5]Don't tell anyone I told you![/speed]"],
	["Old Hesk", "The [swell]Crystal of Ages[/swell] lies beyond the mountains.[pause=0.5] Will you go, [bounce]hero?[/bounce]"],
	["UNIT-7", "[pitch=1.25]Greetings, organic.[/pitch] [shiver]W-warning: anomaly detected.[/shiver]"],
	["The Thing Below", "[droop]Come closer...[/droop][pause=0.6] [shout]CLOSER![/shout]"],
	["Mira", "[bounce]Oh, you're back![/bounce] I saved you a seat [speed=0.6]right by the fire.[/speed]"],
]


class Member extends RefCounted:
	var speaker: BlabberSpeaker
	## The voice preset it started from, e.g. "man".
	var kind := "man"
	## The user's recording for this character, kept while the synth voice is used.
	var recording: BlabberSampleBank
	var use_recording := false
	## The cast's shared vocabulary.
	var vocabulary: BlabberVocabulary
	## Say vocabulary words with their recordings.
	var use_vocabulary := true

	## Speak with the recording (if there is one) or the synth voice.
	func set_use_recording(on: bool) -> void:
		use_recording = on and recording != null
		speaker.voice.sample_bank = recording if use_recording else null
		speaker.voice.vocabulary = vocabulary if use_vocabulary else null

	func set_use_vocabulary(on: bool) -> void:
		use_vocabulary = on
		speaker.voice.vocabulary = vocabulary if use_vocabulary else null

	## Which of the demo's fonts the bubble uses, or "" for another font.
	func font_key() -> String:
		var f: Font = speaker.bubble.font if speaker.bubble else null
		if f == null:
			return ""
		for k in FONTS:
			if f.resource_path == FONTS[k].path:
				return k
		return ""


static func defaults() -> Array:
	var out: Array = []
	for spec in DEFAULTS:
		out.append(make(spec))
	return out


static func make(spec: Dictionary) -> Member:
	var b := BlabberBubbleStyle.new()
	b.bg_color = Color(spec.fill)
	b.border_color = Color(spec.line)
	b.set_border_width_all(spec.lw)
	b.set_corner_radius_all(CORNERS[spec.corner])
	b.text_color = Color(spec.ink)
	b.muted_color = Color(spec.muted)
	b.name_color = Color(spec.tag)
	b.name_text_color = Color(spec.tag_ink)
	b.shadow_color = Color(spec.shadow[0])
	b.shadow_size = spec.shadow[1]
	b.shadow_offset = Vector2(spec.shadow[2], spec.shadow[3])
	b.content_margin_left = 34.0
	b.content_margin_right = 34.0
	b.content_margin_top = 40.0
	b.content_margin_bottom = 26.0
	set_font(b, spec.font)
	var v := BlabberVoice.preset(spec.kind)
	v.mode = BlabberVoice.Mode.PHONETIC if spec.words else BlabberVoice.Mode.GIBBERISH
	var m := Member.new()
	m.kind = spec.kind
	m.speaker = BlabberSpeaker.create(spec.name, v, b)
	return m


## A new character from a preset, in one of the starting looks.
static func make_new(char_name: String, preset_name: String, look: int) -> Member:
	var spec: Dictionary = DEFAULTS[posmod(look, DEFAULTS.size())].duplicate()
	spec.name = char_name
	spec.kind = preset_name
	spec.words = true
	return make(spec)


## A separate copy, for Duplicate.
static func copy_member(m: Member, new_name: String) -> Member:
	var c := Member.new()
	c.kind = m.kind
	c.speaker = m.speaker.copy()
	c.speaker.display_name = new_name
	c.recording = m.recording
	c.vocabulary = m.vocabulary
	c.use_vocabulary = m.use_vocabulary
	c.set_use_recording(m.use_recording)
	return c


## Gives every character the shared vocabulary (each keeps its own on/off).
static func attach_vocabulary(members: Array, vocab: BlabberVocabulary) -> void:
	for m in members:
		m.vocabulary = vocab
		m.set_use_vocabulary(m.use_vocabulary)


## Where the vocabulary is kept, next to the editor's save file.
static func vocabulary_path(save_path := SAVE_PATH) -> String:
	return save_path.get_basename() + "_vocabulary.blab"


## The saved vocabulary, or a new empty one.
static func load_vocabulary(path: String) -> BlabberVocabulary:
	if FileAccess.file_exists(path):
		var r := BlabberVocabulary.read(path)
		if r.ok:
			return r.vocabulary
	return BlabberVocabulary.new()


## Adds the words of another vocabulary (from a file) that aren't there yet,
## and takes for words that are, without repeating a take. Returns how many
## words (x) and takes (y) were added.
static func merge_vocabulary(into: BlabberVocabulary, from: BlabberVocabulary) -> Vector2i:
	var added := Vector2i.ZERO
	for w in from.words:
		var have := into.find(w.text)
		if have == null:
			if into.add_word(w.text) == null:
				continue
			have = into.find(w.text)
			added.x += 1
		for t in w.takes:
			var dup := false
			for h in have.takes:
				dup = dup or _same_audio(h.audio, t.audio)
			if not dup and into.add_clip(w.text, t):
				added.y += 1
	return added


## The same recording, give or take what saving it as 16-bit audio changes.
static func _same_audio(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 0.0002:
			return false
	return true


static func set_font(b: BlabberBubbleStyle, key: String) -> void:
	if not FONTS.has(key):
		return
	b.font = load(FONTS[key].path)
	b.font_size = FONTS[key].size


## The demo font with this family name, if there is one (for opened lines).
static func font_by_name(family: String) -> String:
	for k in FONTS:
		var f: Font = load(FONTS[k].path)
		if f and f.get_font_name() == family:
			return k
	return ""


## A name no other character has: "Aldric", then "Aldric 2", ...
static func unique_name(members: Array, wanted: String) -> String:
	wanted = BlabberVoiceFile.clean_name(wanted)
	if wanted == "":
		wanted = "Someone"
	var taken := {}
	for m in members:
		taken[m.speaker.display_name.to_lower()] = true
	if not taken.has(wanted.to_lower()):
		return wanted
	var n := 2
	while taken.has(("%s %d" % [wanted, n]).to_lower()):
		n += 1
	return "%s %d" % [wanted, n]


## Saves the characters, who's speaking and the line being edited.
static func save_state(members: Array, current: int, line_source: String, path := SAVE_PATH) -> Error:
	var list: Array = []
	for m in members:
		var key: String = m.font_key()
		# Save the recording even while it isn't in use.
		var voice: BlabberVoice = m.speaker.voice
		# The vocabulary is shared, so it's saved once, on its own.
		var in_use := voice.sample_bank
		var vocab := voice.vocabulary
		voice.sample_bank = m.recording
		voice.vocabulary = null
		var d: Dictionary = m.speaker.to_dict(key == "")
		voice.sample_bank = in_use
		voice.vocabulary = vocab
		list.append({"kind": m.kind, "font": key, "use_recording": m.use_recording,
			"use_vocabulary": m.use_vocabulary, "speaker": d})
	var data := {"blabbermouth_editor": FORMAT, "current": current, "line": line_source, "members": list}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	var err := f.get_error()
	f.close()
	return err


## Returns {members, current, line}, or {} if nothing usable is saved.
static func load_state(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed := BlabberVoiceFile.decode_json(FileAccess.get_file_as_bytes(path), "editor")
	if not parsed.ok:
		return {}
	var data: Dictionary = parsed.data
	if typeof(data.get("members")) != TYPE_ARRAY or int(data.get("blabbermouth_editor", 0)) > FORMAT:
		return {}
	var members: Array = []
	for e in data.members:
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("speaker")) != TYPE_DICTIONARY:
			continue
		var r := BlabberSpeaker.from_dict(e.speaker)
		if not r.ok or r.speaker.voice == null:
			continue
		var m := Member.new()
		m.speaker = r.speaker
		if m.speaker.bubble == null:
			m.speaker.bubble = BlabberBubbleStyle.new()
		var key := str(e.get("font", ""))
		if FONTS.has(key):
			var size := m.speaker.bubble.font_size
			set_font(m.speaker.bubble, key)
			m.speaker.bubble.font_size = size
		var kind := str(e.get("kind", "man"))
		m.kind = kind if kind in BlabberVoice.PRESET_NAMES else "man"
		m.recording = m.speaker.voice.sample_bank
		m.use_vocabulary = e.get("use_vocabulary", true) != false
		m.set_use_recording(e.get("use_recording") == true)
		members.append(m)
	if members.is_empty():
		return {}
	var cur = data.get("current", 0)
	var line = data.get("line", "")
	return {"members": members, "current": clampi(int(cur) if typeof(cur) in [TYPE_INT, TYPE_FLOAT] else 0, 0, members.size() - 1),
		"line": line if typeof(line) == TYPE_STRING else ""}
