extends SceneTree
## Headless check: renders presets to WAV and prints timing and levels.
## godot --headless --path . -s tools/test_render.gd -- <out_dir> [text] [phonetic] [presets,comma,separated]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://renders"
	var line := args[1] if args.size() > 1 else "Hello there, traveler! Have you seen my little lantern? It was right here... I swear."
	var phonetic := args.size() > 2 and args[2] == "phonetic"
	var names: Array = BlabberVoice.PRESET_NAMES
	if args.size() > 3:
		names = Array(args[3].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	for name in names:
		var v := BlabberVoice.preset(name)
		if phonetic:
			v.mode = BlabberVoice.Mode.PHONETIC
		var t0 := Time.get_ticks_usec()
		var plan := BlabberParser.build(line, v)
		var synth := BlabberSynth.new(plan.segments, v, 22050)
		var samples := synth.render_all()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var peak := 0.0
		var sq := 0.0
		for s in samples:
			peak = maxf(peak, absf(s))
			sq += s * s
		var secs := samples.size() / 22050.0
		print("%-8s %.2fs audio, render %.0f ms (%.1f%% of realtime), peak %.2f rms %.3f" % [name, secs, ms, ms / 10.0 / secs, peak, sqrt(sq / maxf(1, samples.size()))])
		Blabbermouth.bake(line, v).save_to_wav(out_dir + "/" + name + ".wav")
	quit()
