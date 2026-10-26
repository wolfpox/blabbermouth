extends SceneTree
## Checks voice effects, styled text, line files and the dialogue bubble.
## Exits with code 1 on failure.
## godot --headless --path . -s tools/test_lines.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	_test_bbcode()
	_test_visible_counts()
	_test_voice_effects()
	_test_line_file()
	_test_bake()
	await _test_dialogue()
	print("line tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_bbcode() -> void:
	var cases := {
		"[shiver]Hi[/shiver]": "[shiver]Hi[/shiver]",
		"[emote=scared]Hi[/emote] there": "[shiver]Hi[/shiver] there",
		"[pause=0.5]a[speed=2]b[/speed][pitch=1.2]c": "abc",
		"[b]bold[/b] [shout]GO[/shout]": "[b]bold[/b] [b]GO[/b]",
		"[whisper]psst[/whisper]": "[i]psst[/i]",
		# Overlapping tags still nest properly.
		"[emote=sad]a[shout]b[/emote]c[/shout]": "[droop]a[b]b[/b][/droop][b]c[/b]",
		"[jolt]x[bounce]y[reset]z": "[jolt]x[bounce]y[/bounce][/jolt]z",
		"[emote=happy]a[emote=angry]b[/emote]": "[bounce]a[/bounce][jolt]b[/jolt]",
		"[swell]open": "[swell]open[/swell]",
	}
	for src in cases:
		var got := BlabberParser.to_bbcode(src)
		check(got == cases[src], "to_bbcode(%s) = %s, expected %s" % [src, got, cases[src]])
	check(BlabberParser.to_bbcode("[shout]A[/shout]", 20) == "[font_size=26][b]A[/b][/font_size]", "shout grows with a base size")
	var w := BlabberParser.to_bbcode("[whisper]a[/whisper]", 20, Color("ff0000"))
	check(w == "[color=#ff0000ff][font_size=16][i]a[/i][/font_size][/color]", "whisper is small and muted (%s)" % w)
	check(BlabberParser.to_bbcode("[wave]a[/wave]").begins_with("[wave amp="), "wave uses Godot's wave")


## The styled text must show exactly as many characters as the voice reveals.
func _test_visible_counts() -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	BlabberTextEffects.install(label)
	for src in ["Hello there, [wave]traveler![/wave] Have you seen my [swell]little lantern[/swell]?",
			"[emote=scared]W-what was that noise?[/emote] [pause=0.4]Probably nothing.",
			"[shout]GET OUT[/shout] of [b]my[/b] [whisper]swamp[/whisper]... [jolt]now[/jolt]!",
			"[droop]Oh.[/droop] [bounce][emote=happy]Yay![/emote][/bounce]"]:
		label.text = BlabberParser.to_bbcode(src, 24, Color.GRAY)
		var plan := BlabberParser.build(src, BlabberVoice.preset("man"))
		check(label.get_total_character_count() == plan.visible,
			"visible characters match for %s (%d vs %d)" % [src, label.get_total_character_count(), plan.visible])
	label.free()


func _vowels(text: String, voice := BlabberVoice.preset("man")) -> Array:
	var out: Array = []
	for s in BlabberParser.build(text, voice).segments:
		if s.syl:
			out.append(s)
	return out


func _seconds(text: String) -> float:
	var t := 0.0
	for s in BlabberParser.build(text, BlabberVoice.preset("man")).segments:
		t += s.d
	return t


func _test_voice_effects() -> void:
	var words := "la la la la la la la la"
	# Swell: later syllables are louder and higher than the first.
	var sw := _vowels("[swell]%s[/swell]" % words)
	check(sw[-1].a > sw[0].a * 1.4, "swell gets louder (%.2f -> %.2f)" % [sw[0].a, sw[-1].a])
	# Droop: the end is lower than the start.
	var dr := _vowels("[droop]%s[/droop]" % words)
	var plain := _vowels(words)
	check(dr[-1].p0 / dr[0].p0 < plain[-1].p0 / plain[0].p0 * 0.92, "droop falls in pitch")
	# Wave: the melody moves more than without it.
	check(_spread(_vowels("[wave]%s[/wave]" % words)) > _spread(plain) * 1.25, "wave moves the pitch")
	# Shiver: trembling (jitter and vibrato) on top of the voice.
	var sh := _vowels("[shiver]%s[/shiver]" % words)
	check(sh[0].ji > plain[0].ji and sh[0].vd > plain[0].vd, "shiver trembles")
	# Whisper and an emotion now combine: a sad whisper is slower than a whisper.
	check(_seconds("[emote=sad][whisper]%s[/whisper][/emote]" % words) > _seconds("[whisper]%s[/whisper]" % words) * 1.1,
		"sad whisper is slower than a whisper")
	var both := _vowels("[emote=sad][whisper]%s[/whisper][/emote]" % words)
	check(both[0].vo < 0.5, "sad whisper is still a whisper")
	# Old-style [emote=whisper] still whispers.
	check(_vowels("[emote=whisper]%s[/emote]" % words)[0].vo < 0.5, "[emote=whisper] still works")
	# Effects end where their tag closes.
	var part := _vowels("[jolt]la la[/jolt] la la")
	check(part[-1].ro == plain[-1].ro, "effect stops at its closing tag")


func _spread(vs: Array) -> float:
	var lo := INF
	var hi := 0.0
	for s in vs:
		lo = minf(lo, s.p0)
		hi = maxf(hi, s.p0)
	return hi / lo


func _speaker() -> BlabberSpeaker:
	var bubble := BlabberBubbleStyle.new()
	bubble.bg_color = Color("e3f0cf")
	bubble.border_color = Color("2f4a1a")
	bubble.set_corner_radius_all(4)
	bubble.font_size = 30
	bubble.name_color = Color("2f4a1a")
	bubble.shadow_offset = Vector2(6, 6)
	var f := ThemeDB.fallback_font
	while f is FontVariation and f.base_font:
		f = f.base_font
	bubble.font = f
	return BlabberSpeaker.create("Grub", BlabberVoice.preset("goblin"), bubble)


func _test_line_file() -> void:
	var speaker := _speaker()
	var line := BlabberLine.create("[shout]GET OUT[/shout] of my [jolt]swamp[/jolt]!", speaker)
	# The line has its own copy of the speaker.
	speaker.voice.pitch = 999.0
	speaker.bubble.bg_color = Color.RED
	check(line.voice.pitch == BlabberVoice.preset("goblin").pitch, "line keeps its own voice")
	check(line.bubble.bg_color == Color("e3f0cf"), "line keeps its own bubble")
	check(line.speaker_name == "Grub", "line knows its speaker")
	check(line.bbcode.contains("[jolt]") and line.bbcode.contains("[font_size=39]"), "line bbcode uses the bubble size")
	check(line.plain_text == "GET OUT of my swamp!", "plain text")

	var path := "user://test_line.blab"
	check(BlabberLineFile.write(line, path) == OK, "write line file")
	var r := BlabberLineFile.read(path)
	check(r.ok, "read line file (%s)" % r.get("error"))
	if r.ok:
		var back: BlabberLine = r.line
		check(back.text == line.text, "text survives")
		check(back.speaker_name == "Grub", "name survives")
		check(is_equal_approx(back.voice.pitch, line.voice.pitch) and is_equal_approx(back.voice.growl, line.voice.growl), "voice survives")
		check(back.bubble.bg_color.is_equal_approx(Color("e3f0cf")) and back.bubble.corner_radius_top_left == 4, "bubble survives")
		check(back.bubble.font_size == 30 and back.bubble.shadow_offset == Vector2(6, 6), "bubble details survive")
		var had_font: bool = line.bubble.font is FontFile and line.bubble.font.data.size() > 0
		if had_font:
			check(back.bubble.font is FontFile and back.bubble.font.data == line.bubble.font.data, "embedded font survives")
		var no_font := BlabberLineFile.read(path, false)
		check(no_font.ok and no_font.line.bubble.font == null, "fonts can be skipped")
	# A game can open a line file just for its voice.
	var vr := BlabberVoiceFile.read(path)
	check(vr.ok and is_equal_approx(vr.voice.pitch, line.voice.pitch) and vr.name == "Grub", "line file opens as a voice")
	# And a voice file isn't mistaken for a line.
	BlabberVoiceFile.write(BlabberVoice.preset("robot"), "user://test_voice.blab", "Robot")
	var not_line := BlabberLineFile.read("user://test_voice.blab")
	check(not not_line.ok and not_line.error.contains("voice file"), "voice file is not a line")
	# Damaged and hostile files fail politely.
	var bad := BlabberLineFile.from_bytes('{"blabbermouth_line": 1, "speaker": {"name": "x", "bubble": {"fill": 5, "outline_width": 1e9, "padding": "no", "font": {"data": 7}}}}'.to_utf8_buffer())
	check(bad.ok and bad.line.bubble.border_width_top == 32 and bad.line.bubble.font == null, "bad bubble values are fixed up")
	check(not BlabberLineFile.from_bytes('{"blabbermouth_line": 99}'.to_utf8_buffer()).ok, "newer format refused")
	check(not BlabberLineFile.from_bytes("RIFF....".to_utf8_buffer()).ok, "non-JSON refused")
	# A line file in the project imports as a BlabberLine (needs the plugin's importer).
	var imported = load("res://demo/lines/hello_traveler.blab")
	check(imported is BlabberLine and imported.speaker_name == "Aldric" and imported.voice != null,
		"project .blab line imports as a BlabberLine")
	check(load("res://addons/blabbermouth/voices/man.tres") is BlabberVoice, "voices still load")


func _test_bake() -> void:
	var line := BlabberLine.create("Hello there, [wave]traveler[/wave]! [pause=0.5]I swear.", _speaker())
	var wav := line.bake()
	check(wav.data.size() > 22050, "bake makes audio (%d bytes)" % wav.data.size())
	check(wav.save_to_wav("user://test_line.wav") == OK, "save the baked line as .wav")
	var times := line.word_timings()
	var words: Array = []
	for t in times:
		words.append(t.word)
	check(words == ["Hello", "there", "traveler", "I", "swear"], "word timings list the words (%s)" % [words])
	var ok := true
	for k in times.size():
		ok = ok and times[k].end > times[k].start and (k == 0 or times[k].start >= times[k - 1].end)
	check(ok, "word timings are in order")
	check(times.size() >= 4 and times[3].start - times[2].end > 0.45, "the pause shows in the timings")
	# Effects also work with a recorded voice (here, made from the baked line).
	var pcm := PackedFloat32Array()
	pcm.resize(wav.data.size() / 2)
	for i in pcm.size():
		pcm[i] = wav.data.decode_s16(i * 2) / 32768.0
	var recorded := BlabberVoice.preset("man")
	recorded.sample_bank = BlabberSampleBank.from_samples(pcm, wav.mix_rate)
	check(recorded.sample_bank.slice_count() > 0, "recorded voice has syllables")
	var fx_line := "[shiver]W-what[/shiver] [swell]was that[/swell] [droop]noise[/droop]? [wave]La la[/wave] [jolt]now[/jolt]!"
	check(Blabbermouth.bake(fx_line, recorded).data.size() > 22050, "recorded voice speaks an effects line")


func _test_dialogue() -> void:
	var d := BlabberDialogue.new()
	d.custom_minimum_size = Vector2(600, 0)
	root.add_child(d)
	await process_frame
	var line := BlabberLine.create("[shiver]W-what[/shiver] was [whisper]that[/whisper]?", _speaker())
	var ended := [0]
	d.finished.connect(func() -> void: ended[0] += 1)
	d.say(line)
	check(d.is_speaking(), "dialogue speaks")
	check(d.text_label.text.contains("[shiver]"), "dialogue shows effects")
	check(d.text_label.text.contains("[color=#%s]" % line.bubble.muted_color.to_html()), "whispers use the bubble's muted color")
	check(d.name_label.text == "Grub" and d.name_tag.visible, "name tag shows the speaker")
	check(d.panel.get_theme_stylebox("panel") == line.bubble, "bubble style is used")
	d.skip()
	check(ended[0] == 1 and d.text_label.visible_characters == d.blabbermouth._visible_total, "skip ends and shows the line")
	# Parts can be turned off.
	d.use_bubble_style = false
	d.use_text_style = false
	d.say(line)
	check(not d.text_label.text.contains("[shiver]"), "text style can be off")
	check(d.panel.get_theme_stylebox("panel") != line.bubble, "bubble style can be off")
	d.stop()
	# Silent: no voice given and the speaker's voice turned off.
	d.use_voice = false
	d.say(line)
	check(d.is_speaking(), "silent line still types out")
	d.stop()
	check(ended[0] == 3, "finished once per line (%d)" % ended[0])
	d.queue_free()
	await process_frame
