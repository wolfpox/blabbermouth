extends SceneTree
## Runs the real Blabbermouth node for a few seconds and checks signals fire.
## godot --headless --path . -s tools/test_node.gd

var counts := {"syl": 0, "word": 0, "reveal": 0, "mouth": 0, "done": 0}
var max_mouth := 0.0

func _init() -> void:
	var label := RichTextLabel.new()
	root.add_child(label)
	var b := Blabbermouth.new()
	b.label = label
	b.voice = BlabberVoice.preset("goblin")
	root.add_child(b)
	b.syllable_spoken.connect(func(_i): counts.syl += 1)
	b.word_spoken.connect(func(_w): counts.word += 1)
	b.characters_revealed.connect(func(_c): counts.reveal += 1)
	b.mouth_moved.connect(func(o): counts.mouth += 1; max_mouth = maxf(max_mouth, o))
	b.finished.connect(func(): counts.done += 1)
	await process_frame
	b.speak("Oi! [b]Shiny[/b] things are MINE... [emote=angry]give it!")
	var t := 0.0
	while b.is_speaking() and t < 8.0:
		await process_frame
		t += root.get_process_delta_time()
	print("speaking stopped after %.2fs, label shows %d/%d chars" % [t, label.visible_characters, label.get_total_character_count()])
	print(counts, " max mouth %.2f" % max_mouth)
	quit()
