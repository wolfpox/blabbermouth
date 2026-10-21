extends SceneTree
## Renders every preset saying a line into one WAV, for a quick listen.
## godot --headless --path . -s tools/make_showcase.gd -- <out.wav>

const SHOWCASE := [
	["critter", "Hi hi! Is that a berry? Can I have it? Please please please!"],
	["child", "Mom said I could go to the festival! [emote=excited]Are you coming too?"],
	["woman", "Welcome to the Rusty Anchor. [emote=happy]What can I get you, dear?"],
	["man", "The bridge washed out last night. You'll have to go around... through the forest."],
	["elder", "Ahh... in my day, we walked to the castle. Uphill. Both ways."],
	["goblin", "Oi! Shiny things are MINE! [emote=angry]Give it here!"],
	["monster", "WHO DARES ENTER MY CAVE? [pause=0.3][emote=sad]...oh. You brought cake."],
	["robot", "Greetings, human. Please state your business. Beep."],
	["woman", "[whisper]Don't look now, but we're being followed.[/whisper]"],
	["man", "[shout]RUN![/shout] [emote=scared]It's right behind us!"],
]

func _init() -> void:
	var sr := 22050
	var all := PackedFloat32Array()
	var gap := PackedFloat32Array()
	gap.resize(int(sr * 0.5))
	for item in SHOWCASE:
		var v := BlabberVoice.preset(item[0])
		v.speak_names = true
		var plan := BlabberParser.build(item[1], v)
		all.append_array(BlabberSynth.new(plan.segments, v, sr).render_all())
		all.append_array(gap)
	var data := PackedByteArray()
	data.resize(all.size() * 2)
	for i in all.size():
		data.encode_s16(i * 2, int(clampf(all[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.data = data
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://showcase.wav"
	print("showcase: %.1fs -> %s (%s)" % [all.size() / float(sr), out, error_string(wav.save_to_wav(out))])
	quit()
