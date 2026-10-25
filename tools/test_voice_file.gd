extends SceneTree
## Checks .blab voice files and the voice library. Exits with code 1 on failure.
## godot --headless --path . -s tools/test_voice_file.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	_test_settings_round_trip()
	_test_recording_round_trip()
	_test_bad_files()
	_test_library()
	print("voice file tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_settings_round_trip() -> void:
	var v := BlabberVoice.preset("goblin")
	v.mode = BlabberVoice.Mode.PHONETIC
	v.speak_names = true
	v.pitch = 333.0
	var r := BlabberVoiceFile.from_bytes(BlabberVoiceFile.to_bytes(v, "Grumpy goblin"))
	check(r.ok, "settings round trip loads: " + r.error)
	if not r.ok:
		return
	check(r.name == "Grumpy goblin", "name kept")
	for key in BlabberVoiceFile.settings_of(v):
		var a = v.get(key)
		var b = r.voice.get(key)
		check(typeof(a) == typeof(b) and (a == b or (a is float and is_equal_approx(a, b))), "setting %s kept (%s vs %s)" % [key, a, b])
	check(r.voice.sample_bank == null, "no recording")


func _test_recording_round_trip() -> void:
	# Use a synth line as the "recording".
	var wav := Blabbermouth.bake("Hello there, ba dee go mah loo shee!", BlabberVoice.preset("woman"))
	var rec := BlabberAudioImport.from_wav_stream(wav)
	var bank := BlabberSampleBank.from_samples(rec.samples, rec.rate)
	check(bank.slice_count() > 3, "test recording has slices (%d)" % bank.slice_count())
	bank.set_slice_enabled(1, false)
	var v := BlabberVoice.preset("man")
	v.sample_bank = bank
	v.pitch = bank.reference_pitch() * 1.5
	var t0 := Time.get_ticks_msec()
	var bytes := BlabberVoiceFile.to_bytes(v, "Me")
	var t1 := Time.get_ticks_msec()
	var r := BlabberVoiceFile.from_bytes(bytes)
	var t2 := Time.get_ticks_msec()
	print("recording: %.1fs audio, %d KB file, write %d ms, read %d ms" % [
		bank.audio.size() / float(bank.sample_rate), bytes.size() / 1024, t1 - t0, t2 - t1])
	check(r.ok, "recording round trip loads: " + r.error)
	if not r.ok:
		return
	var b: BlabberSampleBank = r.voice.sample_bank
	check(b != null, "recording kept")
	if b == null:
		return
	check(b.audio.size() == bank.audio.size(), "audio length kept")
	var worst := 0.0
	for i in b.audio.size():
		worst = maxf(worst, absf(b.audio[i] - bank.audio[i]))
	check(worst < 0.001, "audio close to the original (worst %.5f)" % worst)
	check(b.slice_starts == bank.slice_starts and b.slice_ends == bank.slice_ends, "slices kept")
	check(b.slice_enabled == bank.slice_enabled, "removed slices stay removed")
	check(absf(b.base_pitch - bank.base_pitch) < 0.02, "base pitch kept")
	check(is_equal_approx(r.voice.pitch, v.pitch), "pitch kept")
	# And it can speak.
	var out := Blabbermouth.bake("Testing one two.", r.voice)
	check(out.data.size() > 1000, "loaded recording speaks")


func _test_bad_files() -> void:
	check(not BlabberVoiceFile.from_bytes(PackedByteArray()).ok, "empty file rejected")
	check(not BlabberVoiceFile.from_bytes("RIFF....WAVE".to_utf8_buffer()).ok, "audio file rejected")
	check(not BlabberVoiceFile.from_bytes("{not json".to_utf8_buffer()).ok, "broken JSON rejected")
	check(not BlabberVoiceFile.from_bytes("{\"hello\": 1}".to_utf8_buffer()).ok, "other JSON rejected")
	check(not BlabberVoiceFile.from_bytes("{\"blabbermouth_voice\": 99}".to_utf8_buffer()).ok, "newer format rejected")
	# Out-of-range and wrong-type settings are clamped or ignored.
	var r := BlabberVoiceFile.from_bytes(JSON.stringify({"blabbermouth_voice": 1, "name": "../../evil\nname",
		"voice": {"pitch": 1e12, "speed": "fast", "mode": 7, "language_seed": 1e30, "script": "res://x.gd",
		"onsets": "b ".repeat(5000)}}).to_utf8_buffer())
	check(r.ok, "odd settings still load")
	if r.ok:
		check(r.voice.pitch == 1500.0, "pitch clamped (%s)" % r.voice.pitch)
		check(r.voice.speed == 1.0, "wrong type ignored")
		check(r.voice.mode == 1, "enum clamped")
		check(r.voice.get_script() == BlabberVoice, "script can't be replaced")
		check(r.voice.onsets.length() <= BlabberVoiceFile.MAX_TEXT, "long text cut")
		check(not ("/" in r.name) and not ("\n" in r.name) and not r.name.begins_with("."), "name made safe: " + r.name)
	# Slices pointing outside the audio are rejected.
	var bad := JSON.stringify({"blabbermouth_voice": 1, "samples": {"rate": 22050,
		"audio": Marshalls.raw_to_base64(PackedByteArray([0, 0, 0, 0])), "slices": [[0, 99999, 100, 0, 1]]}})
	check(not BlabberVoiceFile.from_bytes(bad.to_utf8_buffer()).ok, "bad slices rejected")


func _test_library() -> void:
	BlabberLibrary.folder = "user://test_voices"
	for e in BlabberLibrary.list():
		DirAccess.remove_absolute(e.path)
	check(BlabberLibrary.list().is_empty(), "library starts empty")
	var s := BlabberLibrary.save(BlabberVoice.preset("robot"), "Beep bot")
	check(s.ok, "save: " + s.error)
	check(BlabberLibrary.has("Beep bot"), "saved voice found")
	check(BlabberLibrary.unique_name("Beep bot") == "Beep bot (2)", "unique name")
	var l := BlabberLibrary.list()
	check(l.size() == 1 and l[0].name == "Beep bot" and not l[0].has_recording, "list shows it")
	var o := BlabberLibrary.open(s.path)
	check(o.ok and is_equal_approx(o.voice.ring_mod_mix, 0.6), "open restores settings")
	var rn := BlabberLibrary.rename(s.path, "beep BOT")
	check(rn.ok and BlabberLibrary.list().size() == 1 and BlabberLibrary.list()[0].name == "beep BOT", "rename (capitals only)")
	rn = BlabberLibrary.rename(rn.path, "Robo")
	check(rn.ok and BlabberLibrary.open(rn.path).ok, "rename")
	BlabberLibrary.save(BlabberVoice.preset("man"), "Other")
	check(not BlabberLibrary.rename(rn.path, "Other").ok, "rename onto another voice refused")
	for e in BlabberLibrary.list():
		check(BlabberLibrary.remove(e.path) == OK, "remove " + e.name)
	check(BlabberLibrary.list().is_empty(), "library empty after removing")
