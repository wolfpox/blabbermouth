extends SceneTree
## Checks the vocabulary: words spoken with real recordings ("takes").
## Matching words and phrases, choosing takes, fitting a take to the voice
## and the line's effects, files, and the node's signals.
## Exits with code 1 on failure.
## godot --headless --path . -s tools/test_vocabulary.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	var vocab := _make_vocab()
	_test_keys()
	_test_matching(vocab)
	_test_plan(vocab)
	_test_sound(vocab)
	_test_files(vocab)
	_test_sets(vocab)
	await _test_node(vocab)
	print("vocabulary tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


## Takes made by the synth, standing in for recordings: "hello" twice (at
## 130 and 150 Hz) and "thank you" once.
func _make_vocab() -> BlabberVocabulary:
	var vocab := BlabberVocabulary.new()
	var speaker := BlabberVoice.preset("man")
	speaker.pitch_variation = 0.0
	for p in [130.0, 150.0]:
		speaker.pitch = p
		check(vocab.add_take("Hello", _samples(Blabbermouth.bake("Hello", speaker)), 22050) != null, "a take is added")
	speaker.pitch = 130.0
	check(vocab.add_take("thank you!", _samples(Blabbermouth.bake("Thank you", speaker)), 22050) != null, "a phrase is added")
	return vocab


func _test_keys() -> void:
	check(BlabberVocabulary.key_of("  Thank   YOU! ") == "thank you", "key: " + BlabberVocabulary.key_of("  Thank   YOU! "))
	check(BlabberVocabulary.key_of("Don’t") == "don't", "curly apostrophes match straight ones")
	var q := BlabberVocabulary.new()
	q.add_word("Ready?")
	var qr := BlabberVocabulary.from_dict(q.to_dict())
	check(qr.ok and qr.vocabulary.words[0].text == "Ready?", "a word's text survives a file as written")
	var v := BlabberVocabulary.new()
	var a := v.add_word("Hello")
	check(v.add_word("hello!") == a and v.words.size() == 1, "the same word isn't added twice")
	check(v.add_word("...") == null, "no letters, no word")
	check(v.add_word("one two three four five") == null, "phrases are at most MAX_PHRASE words")
	check(v.add_take("hello", PackedFloat32Array([0.0, 0.0, 0.0]), 22050) == null, "silence isn't a take")
	var clip := BlabberClip.from_samples(_samples(Blabbermouth.bake("Hi", BlabberVoice.preset("woman"))), 22050)
	# The woman's voice is 215 Hz; a one-word line starts higher, up to ~265 Hz.
	check(clip.pitch > 190.0 and clip.pitch < 300.0, "a take's pitch is measured (%.1f Hz)" % clip.pitch)
	check(clip.pitch_track.size() == ceili(clip.audio.size() / float(BlabberClip.FRAME)), "one pitch per 10 ms")


func _test_matching(vocab: BlabberVocabulary) -> void:
	var found := BlabberParser.recorded_words("Well, HELLO there! Thank you, hello.", vocab)
	var keys: Array = found.map(func(m): return m.key)
	check(keys == ["hello", "thank you", "hello"], "words and phrases are found: %s" % [keys])
	check(found[0].start == 6 and found[0].end == 11, "positions of a word (%d-%d)" % [found[0].start, found[0].end])
	check(found[1].start == 19 and found[1].end == 28, "a phrase covers both words (%d-%d)" % [found[1].start, found[1].end])
	check(BlabberParser.recorded_words("Thank, you", vocab).is_empty(), "punctuation splits a phrase")
	check(BlabberParser.recorded_words("[shout]Hello[/shout] [wave]thank you[/wave]", vocab).size() == 2, "tags don't get in the way")
	var voice := BlabberVoice.preset("man")
	check(BlabberParser.recorded_words("Hello", voice).is_empty(), "a voice without a vocabulary says nothing recorded")
	voice.vocabularies = [vocab]
	check(BlabberParser.recorded_words("Hello", voice).size() == 1, "a voice's vocabulary is used")
	var empty := BlabberVocabulary.new()
	empty.add_word("hello")
	check(BlabberParser.recorded_words("Hello", empty).is_empty(), "a word without takes isn't recorded")


func _heads(segs: Array) -> Array:
	return segs.filter(func(s): return s.has("clip"))


func _test_plan(vocab: BlabberVocabulary) -> void:
	var voice := BlabberVoice.preset("goblin")
	voice.mode = BlabberVoice.Mode.GIBBERISH
	voice.vocabularies = [vocab]
	var text := "Hello, hello, hello! Hello, hello? Thank you."
	var plan := BlabberParser.build(text, voice)
	var heads := _heads(plan.segments)
	check(heads.size() == 6, "every recorded word gets a take (%d)" % heads.size())
	check(plan.visible == BlabberParser.strip_all_tags(text).length(), "visible count is unchanged")
	var picks: Array = heads.slice(0, 5).map(func(s): return s.take)
	var repeats := 0
	for i in range(1, picks.size()):
		if picks[i] == picks[i - 1]:
			repeats += 1
	check(repeats == 0, "the same take isn't used twice in a row: %s" % [picks])
	check(heads[5].word == "Thank you", "a phrase is one word for word_spoken (%s)" % heads[5].word)
	var again := _heads(BlabberParser.build(text, voice).segments)
	check(again.map(func(s): return s.take) == heads.map(func(s): return s.take), "the same line picks the same takes")
	var forced := _heads(BlabberParser.build(text, voice, 1).segments)
	check(forced.slice(0, 5).all(func(s): return s.take == 1), "a take can be asked for")
	# The typewriter still moves through a recorded word.
	var revs: Array = []
	for s in BlabberParser.build("Hello", voice).segments:
		if s.syl:
			revs.append(s.rev)
	check(revs == [3, 5], "a recorded word reveals syllable by syllable: %s" % [revs])
	# Pauses after a recorded word don't copy its take.
	var p2 := BlabberParser.build("Hello[pause=0.3] hello", voice)
	check(_heads(p2.segments).size() == 2, "a pause doesn't repeat the take")
	# Speed tags change how long the take lasts.
	var slow: float = _heads(BlabberParser.build("[speed=0.6]Hello[/speed]", voice).segments)[0].cd
	var normal: float = _heads(BlabberParser.build("Hello", voice).segments)[0].cd
	check(slow > normal * 1.5, "slow stretches the take (%.2f vs %.2f s)" % [slow, normal])
	# Captions: a recorded word lasts as long as its take.
	var times := Blabbermouth.word_timings("Hello there", voice)
	check(times.size() == 2 and times[0].word == "Hello" and absf(times[0].end - times[0].start - normal) < 0.03,
		"word_timings covers the whole take: %s (take %.2f s)" % [times, normal])


func _test_sound(vocab: BlabberVocabulary) -> void:
	for preset in ["man", "woman", "critter"]:
		var v := BlabberVoice.preset(preset)
		v.pitch_variation = 0.0
		v.intonation = 0.0
		v.vocabularies = [vocab]
		var out := _render("Hello", v)
		var p := _pitch(out)
		check(absf(p / v.pitch - 1.0) < 0.15, "%s says the take at their pitch (%.0f Hz, voice %.0f)" % [preset, p, v.pitch])
		check(_rms(out) > 0.02, "%s's recorded word is heard" % preset)
	var v := BlabberVoice.preset("woman")
	v.pitch_variation = 0.0
	v.intonation = 0.0
	v.vocabularies = [vocab]
	vocab.fit_to_voice = false
	var as_recorded := _pitch(_render("Hello", v, 0))
	check(absf(as_recorded / vocab.words[0].takes[0].pitch - 1.0) < 0.12, "not fitted: the recorded pitch (%.0f Hz)" % as_recorded)
	var higher := _pitch(_render("[pitch=1.25]Hello[/pitch]", v, 0))
	check(absf(higher / as_recorded - 1.25) < 0.1, "not fitted, the line's pitch still applies (%.0f Hz)" % higher)
	vocab.fit_to_voice = true
	var shout := _render("[shout]Hello[/shout]", v, 0)
	var plain := _render("Hello", v, 0)
	check(_pitch(shout) > _pitch(plain) * 1.1 and _rms(shout) > _rms(plain), "shout is higher and louder (%.0f vs %.0f Hz, %.3f vs %.3f)" % [_pitch(shout), _pitch(plain), _rms(shout), _rms(plain)])
	var whisper := _render("[whisper]Hello[/whisper]", v)
	check(_rms(whisper) > 0.005 and _voicing(whisper) < _voicing(plain) - 0.1,
		"whisper loses the pitch (%.2f vs %.2f)" % [_voicing(whisper), _voicing(plain)])
	# A sample voice speaks its vocabulary too.
	var bank_voice := BlabberVoice.preset("man")
	bank_voice.sample_bank = BlabberSampleBank.from_samples(_samples(Blabbermouth.bake("ba dee go mah loo shee ka", bank_voice)), 22050)
	bank_voice.pitch = bank_voice.sample_bank.reference_pitch()
	bank_voice.vocabularies = [vocab]
	var plan := BlabberParser.build("Hello friend", bank_voice)
	var eng := BlabberEngine.create(plan.segments, bank_voice, 22050)
	check(eng is BlabberSampler, "sample voice uses the sampler")
	check(_rms(eng.render_all()) > 0.02, "the sampler plays recorded words")
	# Both engines put the take exactly where its word starts.
	for v2: BlabberVoice in [BlabberVoice.preset("robot"), bank_voice]:
		v2.vocabularies = [vocab]
		var p2 := BlabberParser.build("Well, well. Hello there, hello!", v2)
		var e2 := BlabberEngine.create(p2.segments, v2, 22050)
		e2.render_all()
		var starts: Array = []
		for ev in e2.events:
			if p2.segments[ev.y].has("clip"):
				starts.append(ev.x)
		var placed: Array = e2._words._words.map(func(w): return w.start)
		check(starts.size() == 2 and starts == placed, "%s: takes start with their words (%s vs %s)" % [e2.get_class() if not (e2 is BlabberSynth) else "synth", starts, placed])
	# Speed: render time.
	var t0 := Time.get_ticks_msec()
	_render("Hello, thank you. Hello!", BlabberVoice.preset("goblin"))
	print("three recorded words rendered in %d ms" % (Time.get_ticks_msec() - t0))


func _test_files(vocab: BlabberVocabulary) -> void:
	var r := BlabberVocabulary.from_bytes(vocab.to_bytes("Greetings"))
	check(r.ok, "vocabulary file reads back: " + str(r.error))
	if r.ok:
		var v2: BlabberVocabulary = r.vocabulary
		check(v2.resource_name == "Greetings" and v2.words.size() == 2 and v2.find("hello").takes.size() == 2, "words and takes come back")
		var a: BlabberClip = vocab.words[0].takes[0]
		var b: BlabberClip = v2.words[0].takes[0]
		check(a.audio.size() == b.audio.size() and absf(a.pitch - b.pitch) < 0.01 and a.pitch_track.size() == b.pitch_track.size(), "a take comes back the same")
	# Inside a voice file.
	var voice := BlabberVoice.preset("elder")
	voice.vocabularies = [vocab]
	var vr := BlabberVoiceFile.from_bytes(BlabberVoiceFile.to_bytes(voice, "Hesk"))
	check(vr.ok and vr.voice.vocabularies.size() == 1 and vr.voice.vocabularies[0].words.size() == 2, "a voice file keeps its vocabulary")
	check(not BlabberVoiceFile.from_bytes(vocab.to_bytes()).ok, "a vocabulary isn't a voice")
	check(not BlabberLineFile.from_bytes(vocab.to_bytes()).ok, "a vocabulary isn't a line")
	check(BlabberVocabulary.is_vocabulary(vocab.to_bytes()) and not BlabberVocabulary.is_vocabulary(BlabberVoiceFile.to_bytes(voice)), "is_vocabulary")
	# A line file keeps only the words its line uses.
	var line := BlabberLine.create("Hello there, friend.", BlabberSpeaker.create("Hesk", voice))
	var lr := BlabberLineFile.from_bytes(BlabberLineFile.to_bytes(line))
	check(lr.ok, "line with recorded words reads back")
	if lr.ok:
		var lvs: Array = lr.line.voice.vocabularies
		check(lvs.size() == 1 and lvs[0].words.size() == 1 and lvs[0].find("hello") != null, "the line file has just the words it uses")
	line.text = "Nothing recorded here."
	var plain := BlabberLineFile.from_bytes(BlabberLineFile.to_bytes(line))
	check(plain.ok and plain.line.voice.vocabularies.is_empty(), "no recorded words, no vocabulary in the file")
	check(line.speaker.voice.vocabularies[0] == vocab, "a line's speaker shares the vocabulary")
	# Damaged files are refused politely.
	var bad := vocab.to_dict()
	bad.words[0].takes[0].audio = 12
	check(not BlabberVocabulary.from_dict(bad).ok, "a damaged take is refused")
	var no_track := vocab.to_dict()
	no_track.words[0].takes[0].erase("track")
	var nt := BlabberVocabulary.from_dict(no_track)
	check(nt.ok and nt.vocabulary.words[0].takes[0].pitch > 0.0, "a missing pitch track is measured again")
	check(not BlabberVocabulary.from_bytes("{\"blabbermouth_vocabulary\": 99, \"words\": []}".to_utf8_buffer()).ok, "newer versions are refused")
	check(not BlabberVocabulary.from_bytes("RIFF....".to_utf8_buffer()).ok, "not JSON")
	# Files on disk.
	var path := "user://test_vocabulary.blab"
	check(vocab.write(path) == OK and BlabberVocabulary.read(path).ok, "write and read a vocabulary file")
	DirAccess.remove_absolute(path)


## Several sets on one voice: the first that has a word wins, each keeps its
## own fit setting, and voice files can link to set files.
func _test_sets(shared: BlabberVocabulary) -> void:
	var own := BlabberVocabulary.new()
	own.resource_name = "Grunk's words"
	var speaker := BlabberVoice.preset("goblin")
	speaker.pitch_variation = 0.0
	own.add_take("hello", _samples(Blabbermouth.bake("Hello", speaker)), 22050)
	own.add_word("goodbye") # No takes yet: doesn't hide anything.
	shared.resource_name = "Common words"
	var voice := BlabberVoice.preset("goblin")
	voice.vocabularies = [own, shared]
	var found := BlabberParser.recorded_words("Hello, thank you.", voice)
	check(found.size() == 2 and found[0].vocabulary == own and found[0].word == own.find("hello"), "the first set with a word wins")
	check(found.size() == 2 and found[1].vocabulary == shared, "other words come from the next set")
	voice.vocabularies = [shared, own]
	check(BlabberParser.recorded_words("Hello", voice)[0].vocabulary == shared, "order decides")
	# Each set keeps its own fit setting.
	own.fit_to_voice = false
	voice.vocabularies = [own, shared]
	var plan := BlabberParser.build("Hello, thank you.", voice)
	var fits: Array = []
	for sg in plan.segments:
		if sg.has("clip"):
			fits.append(sg.fit)
	check(fits == [false, true], "fit comes from each word's own set: %s" % [fits])
	own.fit_to_voice = true
	# A line file keeps each set it uses, with just those words.
	var line := BlabberLine.create("Hello, thank you.", BlabberSpeaker.create("Grunk", voice))
	var lr := BlabberLineFile.from_bytes(BlabberLineFile.to_bytes(line))
	if check_ok(lr, "a line with two sets reads back"):
		var sets: Array = lr.line.voice.vocabularies
		check(sets.size() == 2 and sets[0].resource_name == "Grunk's words" and sets[0].words.size() == 1
			and sets[1].resource_name == "Common words" and sets[1].words.size() == 1 and sets[1].find("thank you") != null,
			"the line file keeps both sets, trimmed")
	# Copies: the voice file carries both sets.
	var copied := BlabberVoiceFile.from_bytes(BlabberVoiceFile.to_bytes(voice, "Grunk"))
	if check_ok(copied, "a voice with two sets reads back"):
		var sets: Array = copied.voice.vocabularies
		check(sets.size() == 2 and sets[0].resource_name == "Grunk's words" and sets[1].find("hello").takes.size() == 2, "both sets are copied, in order")
	# Links: the voice file names the set files, which are loaded from its folder.
	var dir := "user://test_sets"
	DirAccess.make_dir_recursive_absolute(dir)
	check(shared.file_name() == "Common words.blab", "a set's file name: " + shared.file_name())
	check(own.write(dir.path_join(own.file_name())) == OK and shared.write(dir.path_join(shared.file_name())) == OK, "set files are written")
	var bytes := BlabberVoiceFile.to_bytes(voice, "Grunk", true)
	check(bytes.size() < 4096, "a voice that links to its sets is small (%d bytes)" % bytes.size())
	check(BlabberVoiceFile.write(voice, dir.path_join("Grunk.blab"), "Grunk", true) == OK, "a linked voice file is written")
	var linked := BlabberVoiceFile.read(dir.path_join("Grunk.blab"))
	if check_ok(linked, "a linked voice reads back"):
		var sets: Array = linked.voice.vocabularies
		check(sets.size() == 2 and BlabberVoiceFile.missing_sets(linked.voice).is_empty(), "linked sets are found next to the voice")
		check(sets.size() == 2 and sets[0].find("hello").takes.size() == 1 and sets[1].find("thank you") != null, "linked sets have their words")
		check(BlabberParser.recorded_words("Hello", linked.voice).size() == 1, "a linked voice says its words")
	# Without its folder (or with a set missing), a link is kept as a stand-in.
	var loose := BlabberVoiceFile.from_bytes(bytes)
	if check_ok(loose, "a linked voice reads without its folder"):
		check(BlabberVoiceFile.missing_sets(loose.voice) == PackedStringArray(["Grunk's words", "Common words"]), "missing sets are named: %s" % [BlabberVoiceFile.missing_sets(loose.voice)])
		check(BlabberParser.recorded_words("Hello", loose.voice).is_empty(), "a missing set says nothing recorded")
		var again := BlabberVoiceFile.from_bytes(BlabberVoiceFile.to_bytes(loose.voice))
		check(again.ok and BlabberVoiceFile.missing_sets(again.voice).size() == 2, "a stand-in is saved as a link again")
	# Links can't reach outside the folder.
	var sneaky := {"blabbermouth_voice": 1, "voice": {}, "vocabularies": [{"name": "x", "link": "../secret.blab"}]}
	check(not BlabberVoiceFile.from_bytes(JSON.stringify(sneaky).to_utf8_buffer(), "", dir).ok, "a link with a folder in it is refused")
	# Voice files from before sets keep their one vocabulary.
	var old := {"blabbermouth_voice": 1, "voice": {}, "vocabulary": shared.to_dict()}
	var oldr := BlabberVoiceFile.from_bytes(JSON.stringify(old).to_utf8_buffer())
	check(oldr.ok and oldr.voice.vocabularies.size() == 1 and oldr.voice.vocabularies[0].words.size() == 2, "an older voice file still opens")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	# Copies of a voice share its sets.
	var c := BlabberVoiceFile.copy_voice(voice)
	check(c.vocabularies.size() == 2 and c.vocabularies[0] == own and c.vocabularies != null, "a copied voice shares its sets")
	c.vocabularies.erase(own)
	check(voice.vocabularies.size() == 2, "but has its own list")
	shared.resource_name = ""


func check_ok(r: Dictionary, what: String) -> bool:
	check(r.ok, what + (": " + str(r.error) if not r.ok else ""))
	return r.ok


func _test_node(vocab: BlabberVocabulary) -> void:
	var node := Blabbermouth.new()
	root.add_child(node)
	var label := Label.new()
	root.add_child(label)
	await process_frame
	node.label = label
	var words: Array = []
	var syls := [0]
	var mouth := [0.0]
	node.word_spoken.connect(func(w: String) -> void: words.append(w))
	node.syllable_spoken.connect(func(_i: int) -> void: syls[0] += 1)
	node.mouth_moved.connect(func(m: float) -> void: mouth[0] = maxf(mouth[0], m))
	var voice := BlabberVoice.preset("child")
	voice.vocabularies = [vocab]
	node.speak("Hello! Thank you.", voice)
	var t0 := Time.get_ticks_msec()
	while node.is_speaking() and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	check(not node.is_speaking(), "the line finishes")
	check(words == ["Hello", "Thank you"], "word_spoken for recorded words: %s" % [words])
	check(syls[0] >= 3, "syllables are signalled (%d)" % syls[0])
	check(mouth[0] > 0.2, "the mouth moves with a recorded word (%.2f)" % mouth[0])
	check(label.visible_characters == label.text.length(), "the text is all revealed")
	node.queue_free()
	label.queue_free()


# --- Helpers ----------------------------------------------------------------------

func _render(text: String, voice: BlabberVoice, take := -1) -> PackedFloat32Array:
	var plan := BlabberParser.build(text, voice, take)
	return BlabberEngine.create(plan.segments, voice, 22050).render_all()


func _samples(wav: AudioStreamWAV) -> PackedFloat32Array:
	var d := wav.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for i in out.size():
		out[i] = d.decode_s16(i * 2) / 32768.0
	return out


func _rms(x: PackedFloat32Array) -> float:
	var s := 0.0
	for v in x:
		s += v * v
	return sqrt(s / maxf(1.0, x.size()))


## Median pitch of the pitched parts.
func _pitch(x: PackedFloat32Array) -> float:
	var ps: Array = []
	var i := 0
	while i + BlabberSampleBank.PITCH_SPAN < x.size():
		var p := BlabberSampleBank.frame_pitch(x, i)
		if p > 0.0:
			ps.append(p)
		i += 441
	ps.sort()
	return ps[ps.size() / 2] if not ps.is_empty() else 0.0


## Share of loud frames that have a clear pitch.
func _voicing(x: PackedFloat32Array) -> float:
	var loud := 0
	var pitched := 0
	var i := 0
	var top := 0.0
	for v in x:
		top = maxf(top, absf(v))
	while i + BlabberSampleBank.PITCH_SPAN < x.size():
		var peak := 0.0
		for k in range(i, i + 441):
			peak = maxf(peak, absf(x[k]))
		if peak > top * 0.3:
			loud += 1
			if BlabberSampleBank.frame_pitch(x, i) > 0.0:
				pitched += 1
		i += 441
	return float(pitched) / maxf(1.0, loud)
