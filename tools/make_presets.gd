extends SceneTree
## Regenerates addons/blabbermouth/voices/*.tres from BlabberVoice.preset().
## godot --headless --path . -s tools/make_presets.gd

func _init() -> void:
	for n in BlabberVoice.PRESET_NAMES:
		var path := "res://addons/blabbermouth/voices/%s.tres" % n
		var err := ResourceSaver.save(BlabberVoice.preset(n), path)
		print(path, " -> ", error_string(err))
	quit()
