extends SceneTree
## Regenerates demo/lines/hello_traveler.blab, a sample line file.
## godot --headless --path . -s tools/make_sample_line.gd

func _init() -> void:
	var bubble := BlabberBubbleStyle.new() # Parchment and brown, the defaults.
	bubble.shadow_color = Color(0, 0, 0, 0.25)
	bubble.shadow_offset = Vector2(0, 5)
	var aldric := BlabberSpeaker.create("Aldric", BlabberVoice.preset("man"), bubble)
	var line := BlabberLine.create("Hello there, [wave]traveler![/wave] Have you seen my [swell]little lantern[/swell]? "
		+ "It was right here...[pause=0.5] [whisper]I swear.[/whisper]", aldric)
	DirAccess.make_dir_recursive_absolute("res://demo/lines")
	var path := "res://demo/lines/hello_traveler.blab"
	print(path, " -> ", error_string(BlabberLineFile.write(line, path)))
	quit()
