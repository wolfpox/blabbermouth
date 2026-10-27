extends SceneTree
## Checks the demo editor: the line model, saved characters, and the editor
## screen itself (select words, format them, play, export, the vocabulary).
## Exits with code 1 on failure.
## godot --headless --path . -s tools/test_editor.gd

const LineModel := preload("res://demo/line_model.gd")
const Cast := preload("res://demo/cast.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	_test_model()
	_test_round_trip()
	_test_edit_view()
	_test_cast()
	await _test_screen()
	await _test_vocabulary_screen()
	await _test_touch()
	print("editor tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _model(t: String) -> RefCounted:
	var m := LineModel.new()
	m.set_text(t)
	return m


func _test_model() -> void:
	var m := _model("Hello there, traveler!")
	check(m.snap(14, 16) == Vector2i(13, 22), "snap grows to the whole word with its punctuation (%s)" % m.snap(14, 16))
	check(m.snap(4, 7) == Vector2i(0, 12), "snap across a space takes both words (%s)" % m.snap(4, 7))
	check(m.snap(5, 7) == Vector2i(6, 12), "a leading space is trimmed (%s)" % m.snap(5, 7))
	check(m.snap(5, 6).x == m.snap(5, 6).y, "a selected space alone is nothing")
	m.toggle("wave", 13, 22)
	check(m.to_source() == "Hello there, [wave]traveler![/wave]", "wave tags the word: " + m.to_source())
	check(m.is_on("wave", 13, 22), "is_on after toggle")
	m.toggle("shiver", 13, 22)
	check(m.to_source() == "Hello there, [shiver]traveler![/shiver]", "one motion effect at a time: " + m.to_source())
	m.toggle("shout", 0, 22)
	check(m.to_source() == "[shout]Hello there, [shiver]traveler![/shiver][/shout]", "groups stack: " + m.to_source())
	m.toggle("shout", 0, 22)
	m.toggle("shiver", 13, 22)
	check(m.to_source() == "Hello there, traveler!", "toggling again removes: " + m.to_source())

	# Typing keeps effects in place.
	m = _model("I swear it.")
	m.toggle("whisper", 2, 7)
	m.set_text("Oh, I swear it.")
	check(m.to_source() == "Oh, I [whisper]swear[/whisper] it.", "insert before shifts: " + m.to_source())
	m.set_text("Oh, I sweear it.")
	check(m.to_source() == "Oh, I [whisper]sweear[/whisper] it.", "typing inside keeps the effect: " + m.to_source())
	m.set_text("Oh, I sweear it!!")
	check(m.to_source() == "Oh, I [whisper]sweear[/whisper] it!!", "typing after doesn't inherit: " + m.to_source())
	m.set_text("Oh, it!!")
	check(m.to_source() == "Oh, it!!", "deleting the word drops its effect: " + m.to_source())
	m.set_text("a [b] c")
	check(m.text == "a (b) c", "brackets can't make tags")

	# Pauses.
	m = _model("Wait. Go")
	m.toggle_pause(5)
	check(m.to_source() == "Wait.[pause=0.5] Go", "pause: " + m.to_source())
	m.set_text("Now wait. Go")
	check(m.has_pause(9) and not m.has_pause(5), "pause moves with its word")
	m.set_text("Now go")
	check(m.pauses.is_empty(), "pause goes when its spot is deleted")
	m = _model("Wait. Go")
	m.toggle_pause(5)
	m.toggle("slow", 0, 5)
	check(m.to_source() == "[speed=0.6]Wait.[/speed][pause=0.5] Go", "pause after a closing tag: " + m.to_source())
	m.clear(0, 5)
	check(m.to_source() == "Wait. Go", "clear removes effects and the pause: " + m.to_source())

	# Marks list what the voice does.
	m = _model("Hello there traveler")
	m.toggle("wave", 12, 20)
	m.toggle("shout", 0, 5)
	var marks: Array = m.marks()
	check(marks.size() == 2 and marks[0].fx == ["shout"] and marks[1].start == 12 and marks[1].fx == ["wave"], "marks: %s" % [marks])


func _test_round_trip() -> void:
	var sources := [
		"Hello there, [wave]traveler![/wave] Have you seen my [swell]little lantern[/swell]? It was right here...[pause=0.5] [whisper][speed=0.6]I swear.[/speed][/whisper]",
		"[shout]GET OUT[/shout] of my [jolt]swamp[/jolt]!",
		"[pitch=1.25]Hi[/pitch] [pitch=0.8]low[/pitch] [speed=1.5]fast[/speed]",
	]
	for src in sources:
		var m: RefCounted = LineModel.from_source(src)
		var again: String = m.to_source()
		var m2: RefCounted = LineModel.from_source(again)
		check(m2.to_source() == again, "round trip is stable: " + again)
		check(m.text == BlabberParser.strip_all_tags(src), "plain text survives: " + m.text)
		var voice := BlabberVoice.preset("man")
		check(BlabberParser.build(again, voice).visible == m.text.length(), "visible count matches the text")
	var first: RefCounted = LineModel.from_source(sources[0])
	check(first.to_source() == sources[0], "the sample line comes back as written: " + first.to_source())
	# Old tags turn into their effects.
	var old: RefCounted = LineModel.from_source("[emote=scared]Eek[/emote] [emote=whisper]psst[/emote] [speed=0.8]slow[/speed] [volume=2]x[/volume]")
	check(old.to_source() == "[shiver]Eek[/shiver] [whisper]psst[/whisper] [speed=0.6]slow[/speed] x", "old tags: " + old.to_source())


func _test_edit_view() -> void:
	var m: RefCounted = LineModel.from_source("It was here...[pause=0.5] [shout]I swear.[/shout]")
	var view: Dictionary = m.edit_view(20, Color(0.4, 0.4, 0.4), 15, 23, Color(1, 0.8, 0.2, 0.4))
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	BlabberTextEffects.install(label)
	label.text = view.bbcode
	var parsed := label.get_parsed_text()
	check(view.map.size() == parsed.length() + 1, "one map entry per visible character (%d vs %d)" % [view.map.size(), parsed.length() + 1])
	check(parsed.contains("0.5s"), "pause badge shows: " + parsed)
	check(view.bbcode.contains("[bgcolor="), "selection is highlighted")
	var at_i := parsed.find("I swear")
	check(view.map[at_i] == 15, "map skips the badge (%d)" % view.map[at_i])
	label.free()


func _test_cast() -> void:
	var members: Array = Cast.defaults()
	check(members.size() == 8, "eight starting characters")
	var names := []
	for mem in members:
		names.append(mem.speaker.display_name)
		check(mem.speaker.bubble.font != null, "%s has a font" % mem.speaker.display_name)
	check("Aldric" in names and "UNIT-7" in names, "cast names: %s" % [names])
	var aldric = members[0]
	aldric.speaker.bubble.bg_color = Color("ffeedd")
	aldric.speaker.voice.pitch = 140.0
	# A fake recording, kept while the synth voice is in use.
	var tone := PackedFloat32Array()
	for i in 22050:
		tone.append(sin(i * TAU * 180.0 / 22050.0) * 0.5 * (1.0 if (i / 2000) % 2 == 0 else 0.0))
	aldric.recording = BlabberSampleBank.from_samples(tone, 22050)
	aldric.set_use_recording(false)
	var path := "user://test_editor_state.json"
	check(Cast.save_state(members, 2, "Hello [wave]you[/wave]", path) == OK, "state saves")
	var st: Dictionary = Cast.load_state(path)
	check(not st.is_empty() and st.members.size() == 8, "state loads")
	if not st.is_empty():
		var a = st.members[0]
		check(a.speaker.bubble.bg_color.is_equal_approx(Color("ffeedd")), "bubble color kept")
		check(is_equal_approx(a.speaker.voice.pitch, 140.0), "voice kept")
		check(a.speaker.bubble.font != null and a.speaker.bubble.font.resource_path.begins_with("res://demo/fonts/"), "font comes back from the demo's fonts")
		check(a.recording != null and a.recording.slice_count() > 0 and not a.use_recording and a.speaker.voice.sample_bank == null, "recording kept but not in use")
		check(st.current == 2 and st.line == "Hello [wave]you[/wave]", "current speaker and line kept")
	DirAccess.remove_absolute(path)


func _test_screen() -> void:
	DirAccess.remove_absolute("user://editor_test_scratch.json")
	var scene: Control = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	scene.save_path = "user://editor_test_scratch.json"
	scene.test_size = Vector2i(1280, 900)
	root.add_child(scene)
	for i in 4:
		await process_frame
	var page = scene.line_page
	page.load_source("Hello there, traveler!")
	await process_frame
	# Typing goes into the model.
	page.text_edit.text = "Hello there, traveler!!"
	page.text_edit.text_changed.emit()
	check(page.model.text == "Hello there, traveler!!", "typing updates the line")
	page.load_source("Hello there, traveler!")
	# Tap a word in the bubble: it gets selected, then Wave formats it.
	var label: RichTextLabel = page.dialogue.text_label
	page.select_range(Vector2i(13, 22))
	check(page.sel == Vector2i(13, 22), "range selected")
	page.chips["wave"].pressed.emit()
	check(page.model.to_source() == "Hello there, [wave]traveler![/wave]", "toolbar formats the selection: " + page.model.to_source())
	check(label.text.contains("[wave"), "bubble shows the wave")
	check(page.chips["wave"].on, "wave button shows as on")
	check(page.tags_view.text == "Hello there, [wave]traveler![/wave]", "tags view shows the source")
	# Double-click in the bubble (what a tap turns into) selects a word.
	await process_frame
	var r := label.get_global_rect()
	page.tap_bubble(r.position + Vector2(8, label.size.y * 0.5))
	check(page.sel == Vector2i(0, 5), "tapping the bubble selects the first word (%s)" % page.sel)
	page.chips["shout"].pressed.emit()
	check(page.model.to_source().begins_with("[shout]Hello[/shout]"), "shout the tapped word: " + page.model.to_source())
	# Play and stop.
	page.play_button.pressed.emit()
	check(page.dialogue.is_speaking(), "plays the line")
	await process_frame
	page.play_button.pressed.emit()
	check(not page.dialogue.is_speaking(), "stops")
	check(label.text.contains("[wave"), "bubble back to editing")
	# Switch speaker.
	scene.set_current(5)
	check(page.dialogue.name_label.text == scene.members[5].speaker.display_name, "name tag follows the speaker")
	# Export a line file and read it back.
	var bytes: PackedByteArray = scene.line_file_bytes(true)
	var r2 := BlabberLineFile.from_bytes(bytes)
	check(r2.ok and r2.line.text == page.model.to_source() and r2.line.speaker_name == scene.members[5].speaker.display_name, "exported line reads back")
	check(r2.ok and r2.line.bubble.font != null, "font embedded")
	# Open it as a new line.
	scene.open_line_bytes(bytes, "x.blab")
	check(page.model.to_source() == r2.line.text, "opened line text")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute("user://editor_test_scratch.json")


func _baked(text: String, preset: String) -> PackedFloat32Array:
	var wav := Blabbermouth.bake(text, BlabberVoice.preset(preset))
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in out.size():
		out[i] = wav.data.decode_s16(i * 2) / 32768.0
	return out


func _test_vocabulary_screen() -> void:
	var save := "user://editor_test_vocab.json"
	_clear_editor_files(save)
	var scene: Control = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	scene.save_path = save
	scene.test_size = Vector2i(1280, 900)
	root.add_child(scene)
	for i in 4:
		await process_frame
	check(scene.sets.is_empty() and scene.members.all(func(m): return m.speaker.voice.vocabularies.is_empty()), "no sets to start with")
	scene.show_page("vocabulary")
	var vp = scene.vocabulary_page
	check(vp.visible and vp.no_sets.visible and not vp.set_panel.visible, "the page offers to make a set")
	# A set every character shares.
	vp._new_set()
	var common: BlabberVocabulary = vp.vocab
	check(scene.sets.size() == 1 and common != null and vp.set_panel.visible, "New set makes and shows a set")
	check(Cast.users_of(common, scene.members) == [scene.member()], "a new set is used by the current character")
	vp.name_edit.text = "Common words"
	vp._rename()
	check(common.resource_name == "Common words", "a set can be renamed")
	vp.everyone_button.pressed.emit()
	check(scene.members.all(func(m): return m.uses(common) and m.speaker.voice.vocabularies.has(common)), "Everyone gives it to every character")
	check(vp.empty_label.visible, "an empty set says so")
	vp.add_edit.text = "Hello!"
	vp._add()
	check(common.find("hello") != null and vp.open_key == "hello", "Add word adds and opens it")
	check(vp._record_button != null and vp._load_button != null, "the open word can be recorded or loaded")
	vp._add_audio(common, "hello", _baked("Hello", "woman"), 22050, "")
	check(common.find("hello").takes.size() == 1, "a take is added")
	check(vp.player.playing, "the new take is played in the character's voice")
	vp._add_audio(common, "hello", PackedFloat32Array([0.0, 0.0]), 22050, "")
	check(common.find("hello").takes.size() == 1 and vp.status.text.begins_with("Couldn't hear"), "silence is refused")
	scene._add_member()
	check(scene.member().sets == [common], "a new character gets the sets everyone uses")
	scene.members.remove_at(scene.current)
	scene.set_current(0)
	# The line page shows and plays it.
	scene.show_page("line")
	var page = scene.line_page
	page.load_source("Hello there, [shout]hello![/shout]")
	await process_frame
	var rows := 0
	for c in page.marks_box.get_children():
		if not c.is_queued_for_deletion():
			rows += 1
	check(rows == 3, "the reads card lists the shout and two recorded words (%d)" % rows)
	check(page.source_detail.text.contains("2 recorded words"), "voice source mentions them: " + page.source_detail.text)
	page._update_bars()
	var lr := BlabberLineFile.from_bytes(scene.line_file_bytes(false))
	check(lr.ok and lr.line.voice.vocabularies.size() == 1 and lr.line.voice.vocabularies[0].find("hello") != null, "the exported line carries its recorded word")
	page.play_button.pressed.emit()
	check(page.dialogue.is_speaking(), "plays a line with a recorded word")
	for i in 3:
		await process_frame
	page.play_button.pressed.emit()
	# Grub gets a set of his own, which goes in front of the shared one.
	var grub_i: int = scene.members.find(scene.members.filter(func(m): return m.speaker.display_name == "Grub")[0])
	scene.set_current(grub_i)
	var grub = scene.member()
	scene.show_page("vocabulary")
	vp._new_set()
	var own: BlabberVocabulary = vp.vocab
	vp.name_edit.text = "Common words"
	vp._rename()
	check(own.resource_name == "Common words 2", "set names stay different: " + own.resource_name)
	vp.name_edit.text = "Grub's words"
	vp._rename()
	vp.add_edit.text = "hello"
	vp._add()
	vp._add_audio(own, "hello", _baked("Hello", "goblin"), 22050, "")
	check(Cast.users_of(own, scene.members) == [grub] and grub.sets == [common, own], "Grub uses both sets, the new one last")
	check(BlabberParser.recorded_words("Hello", grub.speaker.voice)[0].vocabulary == common, "the first set wins")
	var ed = scene.cast_page.editor
	scene.show_page("cast")
	ed.refresh()
	var boxes: Array = []
	for row in ed.sets_box.get_children():
		if row is HBoxContainer:
			boxes.append(row)
	check(boxes.size() == 2 and boxes[0].get_child_count() == 3, "the character lists both sets, with up and down buttons")
	(boxes[1].get_child(1) as Button).pressed.emit()
	check(grub.sets == [own, common] and grub.speaker.voice.vocabularies[0] == own, "Up moves a set in front")
	check(BlabberParser.recorded_words("Hello", grub.speaker.voice)[0].vocabulary == own, "and now it wins")
	page.load_source("Hello there")
	scene.show_page("line")
	await process_frame
	var said_from := ""
	for c in page.marks_box.get_children():
		if not c.is_queued_for_deletion():
			for l in c.find_children("*", "Label", true, false):
				said_from += l.text + " "
	check(said_from.contains("from Grub's words"), "the line page says which set a word comes from: " + said_from)
	# Someone stops using the shared set.
	var mira = scene.members[1]
	mira.set_uses(common, false)
	check(BlabberParser.recorded_words("Hello", mira.speaker.voice).is_empty(), "without the set, the voice says it itself")
	scene.set_current(1)
	scene._duplicate_member()
	check(scene.member().sets.is_empty(), "a copy uses the same sets")
	scene.members.remove_at(scene.current)
	scene.set_current(grub_i)
	# Opening set files: the same name adds to it, a new name makes a new set.
	var more := BlabberVocabulary.new()
	more.resource_name = "Common words"
	more.add_take("goodbye", _baked("Goodbye", "man"), 22050)
	more.add_clip("hello", common.find("hello").takes[0])
	scene.open_line_bytes(more.to_bytes(), "more.blab")
	check(scene.sets.size() == 2 and common.find("goodbye") != null and common.find("hello").takes.size() == 1, "opening a set with the same name adds new words, not repeats")
	check(vp.visible and vp.vocab == common, "and shows that set")
	var grunts := BlabberVocabulary.new()
	grunts.add_take("hmph", _baked("Hmph", "monster"), 22050)
	scene.open_line_bytes(grunts.to_bytes(), "Monster grunts.blab")
	var g: BlabberVocabulary = Cast.set_named(scene.sets, "Monster grunts")
	check(scene.sets.size() == 3 and g != null and vp.vocab == g and grub.uses(g), "a new set file becomes a new set, named after the file")
	# A voice file that links to sets by name gets the editor's sets.
	var linked := BlabberVoice.preset("goblin")
	linked.vocabularies.assign([own, g])
	var vr := BlabberVoiceFile.from_bytes(BlabberVoiceFile.to_bytes(linked, "Linked", true))
	check(vr.ok and BlabberVoiceFile.missing_sets(vr.voice).size() == 2, "a linked voice file has stand-ins")
	scene.set_current(0)
	scene._open_voice(vr.voice, "Linked")
	check(scene.member().sets == [own, g], "opening it matches its links to the sets by name")
	# Library: saved voices link to the sets; exports copy them by default.
	var resolved: BlabberVoice = scene._resolve_links(vr.voice)
	check(resolved.vocabularies.size() == 2 and not BlabberVoiceFile.is_link(resolved.vocabularies[0]), "the Voices page can swap links for the sets")
	scene.member().sets = [common]
	scene.member().apply_sets()
	# Saved and loaded again.
	scene.save_now()
	check(DirAccess.get_files_at(Cast.sets_dir(save)).size() == 3, "each set is saved in its own file")
	var n_members: int = scene.members.size()
	var names: Array = scene.sets.map(func(vs): return vs.resource_name)
	scene.queue_free()
	await process_frame
	var again: Control = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	again.save_path = save
	again.test_size = Vector2i(1280, 900)
	root.add_child(again)
	for i in 3:
		await process_frame
	check(again.sets.map(func(vs): return vs.resource_name) == names, "the sets come back in order: %s" % [again.sets.map(func(vs): return vs.resource_name)])
	var c2: BlabberVocabulary = again.sets[0]
	var own2: BlabberVocabulary = Cast.set_named(again.sets, "Grub's words")
	check(c2.find("hello") != null and c2.find("goodbye") != null and own2.find("hello").takes.size() == 1, "their words come back")
	check(again.members.size() == n_members and again.members[grub_i].sets.size() == 3 and again.members[grub_i].sets[0] == own2, "who uses which set, in order, comes back")
	check(not again.members[1].uses(c2) and again.members[2].uses(c2), "and who doesn't")
	check(again.members[grub_i].speaker.voice.vocabularies[0] == own2, "voices get their sets again")
	again.show_page("vocabulary")
	var vp2 = again.vocabulary_page
	vp2.show_sets(again.sets, c2)
	vp2._remove(c2.find("goodbye"))
	check(c2.find("goodbye") == null, "a word can be removed")
	# Deleting a set.
	vp2.show_sets(again.sets, own2)
	vp2._delete_set()
	vp2.confirm.confirmed.emit()
	check(not again.sets.has(own2) and again.members.all(func(m): return not m.uses(own2)), "a deleted set is gone from every character")
	check(DirAccess.get_files_at(Cast.sets_dir(save)).size() == 2, "and its file is removed")
	again.save_now()
	again.queue_free()
	await process_frame
	_clear_editor_files(save)
	await _test_old_vocabulary(save)
	_clear_editor_files(save)


## The one shared vocabulary of the previous version becomes a set.
func _test_old_vocabulary(save: String) -> void:
	var old := BlabberVocabulary.new()
	old.add_take("hello", _baked("Hello", "woman"), 22050)
	old.write(Cast.old_vocabulary_path(save), "Vocabulary")
	var members := Cast.defaults()
	Cast.save_state(members, 0, "Hello", save)
	var f := FileAccess.open(save, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for e in data.members:
		e.erase("sets")
	data.members[1]["use_vocabulary"] = false
	f = FileAccess.open(save, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var scene: Control = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	scene.save_path = save
	scene.test_size = Vector2i(1280, 900)
	root.add_child(scene)
	for i in 3:
		await process_frame
	check(scene.sets.size() == 1 and scene.sets[0].resource_name == "Shared words" and scene.sets[0].find("hello") != null, "the old vocabulary becomes a set")
	check(scene.members[0].uses(scene.sets[0]) and not scene.members[1].uses(scene.sets[0]), "used by the characters that had it on")
	scene.save_now()
	check(not FileAccess.file_exists(Cast.old_vocabulary_path(save)) and DirAccess.get_files_at(Cast.sets_dir(save)).size() == 1, "and is saved as a set file")
	scene.queue_free()
	await process_frame


func _clear_editor_files(save: String) -> void:
	DirAccess.remove_absolute(save)
	DirAccess.remove_absolute(Cast.old_vocabulary_path(save))
	if DirAccess.dir_exists_absolute(Cast.sets_dir(save)):
		for f in DirAccess.get_files_at(Cast.sets_dir(save)):
			DirAccess.remove_absolute(Cast.sets_dir(save).path_join(f))
		DirAccess.remove_absolute(Cast.sets_dir(save))


## A finger drags the page from anywhere; taps still press things.
func _test_touch() -> void:
	var save := "user://editor_test_touch.json"
	DirAccess.remove_absolute(save)
	var scene: Control = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	scene.save_path = save
	scene.test_size = Vector2i(360, 780)
	root.add_child(scene)
	for i in 4:
		await process_frame
	var page = scene.line_page
	page.load_source("Hello there, traveler!")
	for i in 3:
		await process_frame
	var chip: Control = page.chips["wave"]
	var at := chip.get_global_rect().get_center()
	scene.scroll.scroll_vertical = 0
	# Drag up from a chip: the page scrolls and the chip isn't pressed.
	await _touch(at, at + Vector2(0, -150))
	check(scene.scroll.scroll_vertical > 100, "dragging over a chip scrolls the page (%d)" % scene.scroll.scroll_vertical)
	check(page.model.to_source() == "Hello there, traveler!", "a drag doesn't press the chip: " + page.model.to_source())
	# Let go mid-drag and it glides on, then settles.
	var last := -1
	for i in 600:
		if scene.scroll.scroll_vertical == last:
			break
		last = scene.scroll.scroll_vertical
		await create_timer(0.03).timeout
	scene.scroll.scroll_vertical = 0
	await process_frame
	# A tap still presses it.
	await _touch(at, at)
	check(page.model.to_source() == "[wave]Hello there, traveler![/wave]", "a tap presses the chip: " + page.model.to_source())
	check(scene.scroll.scroll_vertical == 0, "a tap doesn't scroll")
	# A sideways drag goes to what's under the finger, and doesn't scroll.
	await _touch(at, at + Vector2(60, 4))
	check(scene.scroll.scroll_vertical == 0, "a sideways drag doesn't scroll")
	# Everything fits a 360 px phone, even with effects piled on long text.
	for i in scene.members.size():
		if scene.members[i].speaker.display_name == "UNIT-7":
			scene.set_current(i)
	page.load_source("W-what was that noise?[pause=0.5] Probably nothing. Probably.")
	for fx in ["shout", "wave", "slow", "high"]:
		page.select_range(Vector2i(0, 9999))
		page.chips[fx].pressed.emit()
	page._toggle_pause()
	page.select_range(Vector2i(23, 50))
	for i in 3:
		await process_frame
	var need: float = scene.scroll.get_combined_minimum_size().x
	check(need <= 360.0, "the line page fits a phone with effects piled on (%d px)" % need)
	for p in ["cast", "vocabulary", "voices"]:
		scene.show_page(p)
		await process_frame
		need = scene.scroll.get_combined_minimum_size().x
		check(need <= 360.0, "the %s page fits a phone (%d px)" % [p, need])
	scene.show_page("line")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(save)


## Presses at a canvas point, moves to another in steps, and lets go.
func _touch(from: Vector2, to: Vector2) -> void:
	var xf := root.get_final_transform()
	var steps := 6 if from != to else 0
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = xf * from
	Input.parse_input_event(t)
	Input.flush_buffered_events()
	await process_frame
	for i in steps:
		var d := InputEventScreenDrag.new()
		d.position = xf * from.lerp(to, float(i + 1) / steps)
		d.relative = xf.basis_xform((to - from) / steps)
		Input.parse_input_event(d)
		Input.flush_buffered_events()
		await process_frame
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = xf * to
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
