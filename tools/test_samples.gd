extends SceneTree
## Imports recordings, slices them, and speaks a line with each.
## godot --headless --path . -s tools/test_samples.gd -- <out_dir> <file> [file...]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0]
	var importer := BlabberAudioImport.new()
	root.add_child(importer)
	await process_frame
	for path in args.slice(1):
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await importer.load_file(path)
		var t1 := Time.get_ticks_msec()
		if not r.ok:
			print(path.get_file(), ": FAILED ", r.error)
			continue
		var bank := BlabberSampleBank.from_samples(r.samples, r.rate)
		var t2 := Time.get_ticks_msec()
		var ps := []
		for i in bank.slice_count():
			ps.append("%.2fs:%d Hz/b%.2f" % [bank.slice_starts[i] / 22050.0, int(bank.slice_pitch[i]), bank.slice_brightness[i]])
		print("%s: %.2fs @%d Hz, load %d ms, analyze %d ms, %d slices, base %.0f Hz" % [path.get_file(), r.samples.size() / float(r.rate), r.rate, t1 - t0, t2 - t1, bank.slice_count(), bank.base_pitch])
		print("   ", " ".join(ps))
		var line := "Hello there, traveler! Have you seen my little lantern? It was right here... I swear."
		for variant in [["as_is", 1.0, 1.0], ["squeaky", 2.0, 1.5], ["giant", 0.5, 0.7]]:
			var v := BlabberVoice.preset("woman")
			v.sample_bank = bank
			v.pitch = bank.reference_pitch() * variant[1]
			v.formant_scale = variant[2]
			var t3 := Time.get_ticks_msec()
			var wav := Blabbermouth.bake(line, v)
			var secs := wav.data.size() / 2.0 / 22050.0
			print("   %-8s %.2fs audio in %d ms" % [variant[0], secs, Time.get_ticks_msec() - t3])
			wav.save_to_wav("%s/%s_%s.wav" % [out_dir, path.get_file().get_basename(), variant[0]])
	quit()
