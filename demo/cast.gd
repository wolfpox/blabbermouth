extends RefCounted
## The demo's characters. Each is a BlabberSpeaker (name, voice, bubble) plus
## what the editor needs around it: the voice preset it started from, a
## recording that's kept even while the synth voice is in use, and which
## sets of recorded words (vocabularies) it uses.

const SAVE_PATH := "user://editor.json"
const FORMAT := 1
const DEFAULT_SET_NAME := "Recorded words"

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
	## The sets of recorded words this character uses. When two have the
	## same word, the first one wins.
	var sets: Array = []

	## Speak with the recording (if there is one) or the synth voice.
	func set_use_recording(on: bool) -> void:
		use_recording = on and recording != null
		speaker.voice.sample_bank = recording if use_recording else null
		apply_sets()

	## Gives the voice this character's sets (after they or the voice change).
	func apply_sets() -> void:
		speaker.voice.vocabularies.assign(sets)

	func uses(vs: BlabberVocabulary) -> bool:
		return sets.has(vs)

	## Starts or stops using a set. A new one goes last.
	func set_uses(vs: BlabberVocabulary, on: bool) -> void:
		if on and not sets.has(vs):
			sets.append(vs)
		elif not on:
			sets.erase(vs)
		apply_sets()

	## Moves a set earlier (-1) or later (+1) in the list.
	func move_set(vs: BlabberVocabulary, by: int) -> void:
		var i := sets.find(vs)
		var j := i + by
		if i < 0 or j < 0 or j >= sets.size():
			return
		sets[i] = sets[j]
		sets[j] = vs
		apply_sets()

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
	c.sets = m.sets.duplicate()
	c.set_use_recording(m.use_recording)
	return c


# --- Sets of recorded words ------------------------------------------------------

## The sets every character uses (a new character starts with these).
static func shared_sets(members: Array, sets: Array) -> Array:
	var out: Array = []
	for vs in sets:
		var all := not members.is_empty()
		for m in members:
			all = all and m.uses(vs)
		if all:
			out.append(vs)
	return out


## The characters that use a set.
static func users_of(vs: BlabberVocabulary, members: Array) -> Array:
	return members.filter(func(m) -> bool: return m.uses(vs))


## A set name no other set has: "Goblin words", then "Goblin words 2", ...
static func unique_set_name(sets: Array, wanted: String, except: BlabberVocabulary = null) -> String:
	wanted = BlabberVoiceFile.clean_name(wanted)
	if wanted == "":
		wanted = DEFAULT_SET_NAME
	var taken := {}
	for vs in sets:
		if vs != except:
			taken[vs.resource_name.to_lower()] = true
	if not taken.has(wanted.to_lower()):
		return wanted
	var n := 2
	while taken.has(("%s %d" % [wanted, n]).to_lower()):
		n += 1
	return "%s %d" % [wanted, n]


## The set with this name (any case), or null.
static func set_named(sets: Array, set_name: String) -> BlabberVocabulary:
	for vs in sets:
		if vs.resource_name.to_lower() == set_name.to_lower():
			return vs
	return null


## Each set's id: its file name in the sets folder. Kept here rather than on
## the set, so sets saved for games don't carry it.
static var _set_ids := {}


static func set_id(vs: BlabberVocabulary) -> String:
	return _set_ids.get(vs, "")


## Forgets a set's id (for a set that's deleted, or that came from a file).
static func forget_id(vs: BlabberVocabulary) -> void:
	_set_ids.erase(vs)


## Gives a set an id (its file name in the sets folder) if it has none.
static func give_id(vs: BlabberVocabulary, sets: Array) -> void:
	if set_id(vs) != "":
		return
	var taken := {}
	for other in sets:
		taken[set_id(other)] = true
	var n := 1
	while taken.has("set%d" % n):
		n += 1
	_set_ids[vs] = "set%d" % n


## Where the sets are kept, one file each, next to the editor's save file.
static func sets_dir(save_path := SAVE_PATH) -> String:
	return save_path.get_basename() + "_sets"


## Where older versions kept their one shared vocabulary.
static func old_vocabulary_path(save_path := SAVE_PATH) -> String:
	return save_path.get_basename() + "_vocabulary.blab"


static func save_set(vs: BlabberVocabulary, save_path := SAVE_PATH) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(sets_dir(save_path))
	if err != OK:
		return err
	return vs.write(sets_dir(save_path).path_join(set_id(vs) + ".blab"))


static func delete_set_file(vs: BlabberVocabulary, save_path := SAVE_PATH) -> void:
	var path := sets_dir(save_path).path_join(set_id(vs) + ".blab")
	if set_id(vs) != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## The saved sets: those listed in order first, then any others.
static func load_sets(save_path := SAVE_PATH, order: Array = []) -> Array:
	var dir := sets_dir(save_path)
	var by_id := {}
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() != BlabberVoiceFile.EXTENSION:
				continue
			var r := BlabberVocabulary.read(dir.path_join(f))
			if not r.ok:
				continue
			var vs: BlabberVocabulary = r.vocabulary
			if vs.resource_name == "":
				vs.resource_name = DEFAULT_SET_NAME
			_set_ids[vs] = f.get_basename()
			by_id[f.get_basename()] = vs
	var out: Array = []
	for id in order:
		if by_id.has(str(id)):
			out.append(by_id[str(id)])
			by_id.erase(str(id))
	var rest := by_id.keys()
	rest.sort()
	for id in rest:
		out.append(by_id[id])
	return out


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


## Saves the characters, who's speaking and the line being edited. The sets
## are saved on their own (save_set()); this keeps their order and who uses them.
static func save_state(members: Array, current: int, line_source: String, path := SAVE_PATH, sets: Array = []) -> Error:
	var list: Array = []
	for m in members:
		var key: String = m.font_key()
		# Save the recording even while it isn't in use.
		var voice: BlabberVoice = m.speaker.voice
		var in_use := voice.sample_bank
		voice.sample_bank = m.recording
		voice.vocabularies.clear()
		var d: Dictionary = m.speaker.to_dict(key == "")
		voice.sample_bank = in_use
		m.apply_sets()
		list.append({"kind": m.kind, "font": key, "use_recording": m.use_recording,
			"sets": m.sets.map(func(vs) -> String: return set_id(vs)), "speaker": d})
	var data := {"blabbermouth_editor": FORMAT, "current": current, "line": line_source, "members": list,
		"sets": sets.map(func(vs) -> String: return set_id(vs))}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	var err := f.get_error()
	f.close()
	return err


## Returns {members, current, line, sets, migrated}, or {sets} alone if no
## characters are saved. migrated: the sets came from an older version's one
## vocabulary, and need saving.
static func load_state(path := SAVE_PATH) -> Dictionary:
	var data := {}
	if FileAccess.file_exists(path):
		var parsed := BlabberVoiceFile.decode_json(FileAccess.get_file_as_bytes(path), "editor")
		if parsed.ok and typeof(parsed.data.get("members")) == TYPE_ARRAY and int(parsed.data.get("blabbermouth_editor", 0)) <= FORMAT:
			data = parsed.data
	var order = data.get("sets", [])
	var sets := load_sets(path, order if typeof(order) == TYPE_ARRAY else [])
	var by_id := {}
	for vs in sets:
		by_id[set_id(vs)] = vs
	# Older versions had one vocabulary that every character could switch on.
	var old: BlabberVocabulary = null
	if sets.is_empty() and FileAccess.file_exists(old_vocabulary_path(path)):
		var r := BlabberVocabulary.read(old_vocabulary_path(path))
		if r.ok and not r.vocabulary.words.is_empty():
			old = r.vocabulary
			if old.resource_name in ["", "Vocabulary"]:
				old.resource_name = "Shared words"
			give_id(old, sets)
			sets.append(old)
	if data.is_empty():
		return {"sets": sets, "migrated": old != null}
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
		var ids = e.get("sets")
		if typeof(ids) == TYPE_ARRAY:
			for id in ids:
				if by_id.has(str(id)) and not m.sets.has(by_id[str(id)]):
					m.sets.append(by_id[str(id)])
		elif old != null and e.get("use_vocabulary", true) != false:
			m.sets = [old]
		m.set_use_recording(e.get("use_recording") == true)
		members.append(m)
	if members.is_empty():
		return {"sets": sets, "migrated": old != null}
	var cur = data.get("current", 0)
	var line = data.get("line", "")
	return {"members": members, "current": clampi(int(cur) if typeof(cur) in [TYPE_INT, TYPE_FLOAT] else 0, 0, members.size() - 1),
		"line": line if typeof(line) == TYPE_STRING else "", "sets": sets, "migrated": old != null}
