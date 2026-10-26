@tool
@icon("res://addons/blabbermouth/icon.svg")
class_name BlabberLine
extends Resource
## One line of dialogue, with its own copy of the speaker. A game can use any
## part of it on its own:
## [codeblock]
## var line: BlabberLine = load("res://lines/hello_traveler.blab")
## $Dialogue.say(line)                    # bubble, styled text and voice
## $Blabbermouth.speak(line.text, line.voice)   # just the voice
## $MyLabel.text = line.bbcode            # just the styled text
## $MyPanel.add_theme_stylebox_override("panel", line.bubble)   # just the bubble
## [/codeblock]
## Or bake it to a sound file with bake() and use it anywhere.

## The words, with Blabbermouth tags like [shiver] or [pause=0.5].
@export_multiline var text := ""
@export var speaker: BlabberSpeaker

## The speaker's voice (null if none).
var voice: BlabberVoice:
	get:
		return speaker.voice if speaker else null
## The speaker's bubble style (null if none). Also a StyleBox.
var bubble: BlabberBubbleStyle:
	get:
		return speaker.bubble if speaker else null
## The speaker's name, for the name tag.
var speaker_name: String:
	get:
		return speaker.display_name if speaker else ""
## The text as RichTextLabel BBCode with the effects showing, sized and
## colored for the bubble. The label needs BlabberTextEffects.install().
var bbcode: String:
	get:
		var b := bubble
		return BlabberParser.to_bbcode(text, b.font_size if b else 0, b.muted_color if b else Color(0, 0, 0, 0))
## The words with every tag removed.
var plain_text: String:
	get:
		return BlabberParser.strip_all_tags(text)


## A new line with its own copy of the speaker.
static func create(p_text: String, p_speaker: BlabberSpeaker) -> BlabberLine:
	var line := BlabberLine.new()
	line.text = p_text
	line.speaker = p_speaker.copy() if p_speaker else null
	return line


## The spoken line as audio. Save it with save_to_wav() to use without Blabbermouth.
func bake(sample_rate := 22050) -> AudioStreamWAV:
	return Blabbermouth.bake(text, _voice_or_default(), sample_rate)


## When each word starts and ends, in seconds: [{word, start, end}, ...].
func word_timings(sample_rate := 22050) -> Array:
	return Blabbermouth.word_timings(text, _voice_or_default(), sample_rate)


func _voice_or_default() -> BlabberVoice:
	return voice if voice else BlabberVoice.preset("man")
