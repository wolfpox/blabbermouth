@icon("res://addons/blabbermouth/icon.svg")
class_name Blabbermouth
extends Node
## Speaks dialogue text as character mumbling.
##
## Add it to a character, pick a [member voice], then call [method speak].
## Connect [member label_path] to a Label or RichTextLabel for a typewriter
## effect that stays in sync with the voice, and use [signal mouth_moved]
## or [member mouth_openness] for lip-sync.
##
## Inline tags you can use in the text:
## [codeblock]
## [pause=0.5]  [speed=1.5]...[/speed]  [pitch=1.2]...[/pitch]
## [volume=0.5]...[/volume]  [emote=angry]...[/emote]
## [whisper]...[/whisper]  [shout]...[/shout]  [reset]
## [shiver] [wave] [swell] [bounce] [droop] [jolt] ...[/name]
## [/codeblock]
## Give the voice a [member BlabberVoice.vocabulary] and its words are
## spoken with real recordings, fitted to the voice and the tags.
## Emotions: happy, excited, angry, sad, scared. Effects, an emotion and
## whisper or shout can all be combined. On a RichTextLabel the effects,
## emotions, whisper and shout also show in the text (see [member text_effects]).

## Emitted when a line starts playing.
signal started(text: String)
## Emitted when each syllable starts. char_index is its position in the visible text.
signal syllable_spoken(char_index: int)
## Emitted when each word starts.
signal word_spoken(word: String)
## Emitted when more of the text should be shown. Matches visible_characters.
signal characters_revealed(count: int)
## Emitted every frame while speaking. 0 = closed, 1 = wide open.
signal mouth_moved(openness: float)
## Emitted once for every line when it ends: played to the end, skipped,
## or cut off by stop() or a new speak(). So [code]await finished[/code]
## always returns.
signal finished
## Emitted when a line is cut off by stop() or a new speak(), just before
## finished. Use it to tell a cut-off line from one that played out.
signal interrupted

@export var voice: BlabberVoice
## An AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D. Leave empty to create one.
@export var player_path: NodePath
## Optional Label or RichTextLabel to reveal in sync with the voice.
@export var label_path: NodePath
@export var bus: StringName = &"Master"
## On a RichTextLabel with BBCode on, show what the voice does: moving text for
## effects and emotions, bold for shout, small italics for whisper.
## Off: Blabbermouth tags are just removed.
@export var text_effects := true
## Color for whispered words. Transparent: the label's text color, faded.
@export var whisper_color := Color(0, 0, 0, 0)
## Lower is cheaper. 22050 sounds fine for most voices.
@export_enum("16000:16000", "22050:22050", "32000:32000", "44100:44100") var sample_rate: int = 22050

## Current mouth openness, for lip-sync in _process.
var mouth_openness := 0.0
## The audio player in use. Can be set from code instead of player_path.
var player: Node
## The label in use. Can be set from code instead of label_path.
var label: Node

var _synth: BlabberEngine
var _playback: AudioStreamGeneratorPlayback
var _visible_total := 0
var _event_i := 0
var _revealed := 0
var _speaking := false


func _ready() -> void:
	if player == null and not player_path.is_empty():
		player = get_node(player_path)
	if player == null:
		var p := AudioStreamPlayer.new()
		p.name = "VoicePlayer"
		p.bus = bus
		add_child(p)
		player = p
	if label == null and not label_path.is_empty():
		label = get_node(label_path)
	set_process(false)


## Starts speaking. Any line already playing is cut off (it emits
## interrupted and finished first).
func speak(text: String, override_voice: BlabberVoice = null) -> void:
	if player == null:
		push_error("Blabbermouth: speak() called before the node is ready.")
		return
	# Code waiting on the old line may start another line from its finished
	# handler; end those too, so this newest line wins and nothing waits forever.
	var guard := 0
	while _speaking and guard < 16:
		_end_line(false, true)
		guard += 1
	var v := override_voice if override_voice else voice
	if v == null:
		v = BlabberVoice.preset("man")
	var plan := BlabberParser.build(text, v)
	_synth = BlabberEngine.create(plan.segments, v, sample_rate)
	_visible_total = plan.visible
	_event_i = 0
	_revealed = 0
	if label:
		var rich: bool = label is RichTextLabel and label.bbcode_enabled
		if rich and text_effects:
			BlabberTextEffects.install(label)
			var muted := whisper_color
			if muted.a <= 0.0:
				muted = label.get_theme_color("default_color")
				muted.a *= 0.7
			label.text = BlabberParser.to_bbcode(text, label.get_theme_font_size("normal_font_size"), muted)
		else:
			label.text = plan.display_text if rich else plan.plain_text
		label.visible_characters = 0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = 0.15
	player.stream = gen
	player.play()
	_playback = player.get_stream_playback()
	_fill()
	_speaking = true
	set_process(true)
	started.emit(text)


## Stops speaking without revealing the rest of the text. Emits
## interrupted, then finished.
func stop() -> void:
	if _speaking:
		_end_line(false, true)


## Stops speaking, reveals the whole line and emits finished.
func skip() -> void:
	if _speaking:
		_end_line(true, false)


func is_speaking() -> bool:
	return _speaking


## Text with Blabbermouth tags removed (BBCode is kept).
static func strip_tags(text: String) -> String:
	return BlabberParser.strip_tags(text)


## Renders a line to an AudioStreamWAV, e.g. to cache lines or save with save_to_wav().
## take picks which recording of vocabulary words to use (-1: each word chooses).
static func bake(text: String, p_voice: BlabberVoice, p_sample_rate: int = 22050, take := -1) -> AudioStreamWAV:
	var plan := BlabberParser.build(text, p_voice, take)
	var synth := BlabberEngine.create(plan.segments, p_voice, p_sample_rate)
	var samples := synth.render_all()
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = p_sample_rate
	wav.stereo = false
	wav.data = data
	return wav


## When each word starts and ends, in seconds, for captions or lip-sync in
## another engine. Returns [{word, start, end}, ...].
static func word_timings(text: String, p_voice: BlabberVoice, p_sample_rate: int = 22050) -> Array:
	var plan := BlabberParser.build(text, p_voice)
	var synth := BlabberEngine.create(plan.segments, p_voice, p_sample_rate)
	synth.render_all()
	var out: Array = []
	for ev in synth.events:
		var seg: Dictionary = synth.segments[ev.y]
		var t := float(ev.x) / p_sample_rate
		if not out.is_empty() and out[-1].end < 0.0 and (seg.word != "" or seg.ph == ""):
			out[-1].end = t
		if seg.word != "":
			out.append({"word": seg.word, "start": t, "end": -1.0})
	if not out.is_empty() and out[-1].end < 0.0:
		out[-1].end = float(synth.end_sample) / p_sample_rate
	return out


func _process(_delta: float) -> void:
	if not _speaking:
		return
	_fill()
	var played := int(player.get_playback_position() * sample_rate)
	var events := _synth.events
	while _event_i < events.size() and events[_event_i].x <= played:
		var seg: Dictionary = _synth.segments[events[_event_i].y]
		if seg.rev > _revealed:
			_reveal(seg.rev)
		if seg.word != "":
			word_spoken.emit(seg.word)
		if seg.syl:
			syllable_spoken.emit(maxi(seg.rev - 1, 0))
		_event_i += 1
	_set_mouth(_synth.mouth_at(played))
	if _synth.finished and played >= _synth.end_sample:
		_end_line(true, false)


func _end_line(reveal_all: bool, cut: bool) -> void:
	_speaking = false
	player.stop()
	set_process(false)
	_set_mouth(0.0)
	if reveal_all:
		_reveal(_visible_total)
	if cut:
		interrupted.emit()
	finished.emit()


func _fill() -> void:
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var mono := _synth.render(n)
	var stereo := PackedVector2Array()
	stereo.resize(n)
	for i in n:
		stereo[i] = Vector2(mono[i], mono[i])
	_playback.push_buffer(stereo)


func _reveal(count: int) -> void:
	count = mini(count, _visible_total)
	if count <= _revealed and count != _visible_total:
		return
	_revealed = count
	if label:
		label.visible_characters = count
	characters_revealed.emit(count)


func _set_mouth(value: float) -> void:
	mouth_openness = value
	mouth_moved.emit(value)
