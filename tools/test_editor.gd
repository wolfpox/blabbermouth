extends SceneTree
## Checks the demo editor: the line model, saved characters, and the editor
## screen itself (select words, format them, play, export).
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
