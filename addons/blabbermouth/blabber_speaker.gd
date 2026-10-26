@tool
class_name BlabberSpeaker
extends Resource
## A character who speaks: a name, a voice and a speech bubble style.
## Each BlabberLine keeps its own copy, so a line file works on its own.

## Shown on the bubble's name tag.
@export var display_name := ""
@export var voice: BlabberVoice
@export var bubble: BlabberBubbleStyle


static func create(p_name: String, p_voice: BlabberVoice, p_bubble: BlabberBubbleStyle = null) -> BlabberSpeaker:
	var s := BlabberSpeaker.new()
	s.display_name = p_name
	s.voice = p_voice
	s.bubble = p_bubble
	return s


## A separate copy: changing it (or the original) doesn't affect the other.
## The font is shared, since fonts don't change.
func copy() -> BlabberSpeaker:
	var s := BlabberSpeaker.new()
	s.display_name = display_name
	if voice:
		s.voice = BlabberVoiceFile.copy_voice(voice)
	if bubble:
		s.bubble = bubble.duplicate()
	return s


## Plain values for a line file.
func to_dict(embed_font := true) -> Dictionary:
	var d := {"name": BlabberVoiceFile.clean_name(display_name)}
	if voice:
		d.merge(BlabberVoiceFile.voice_to_dict(voice))
	if bubble:
		d["bubble"] = bubble.to_dict(embed_font)
	return d


## Rebuilds a speaker from to_dict() values. Returns {ok, speaker, error}.
static func from_dict(d: Dictionary, load_font := true) -> Dictionary:
	var s := BlabberSpeaker.new()
	s.display_name = BlabberVoiceFile.clean_name(str(d.get("name", "")))
	if d.has("voice"):
		var r := BlabberVoiceFile.voice_from_dict(d)
		if not r.ok:
			return {"ok": false, "speaker": null, "error": r.error}
		s.voice = r.voice
		s.voice.resource_name = s.display_name
	if typeof(d.get("bubble")) == TYPE_DICTIONARY:
		s.bubble = BlabberBubbleStyle.from_dict(d.bubble, load_font)
	return {"ok": true, "speaker": s, "error": ""}
