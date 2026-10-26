class_name BlabberEngine
extends RefCounted
## Shared interface for the things that turn a speech plan into audio:
## BlabberSynth (synthesized voice) and BlabberSampler (recorded voice).

var sample_rate := 22050.0
var segments: Array = []
var voice: BlabberVoice
## True once every sample of the line has been rendered.
var finished := false
## Sample position where the line ends (valid once finished).
var end_sample := 0
## [sample_pos, segment_index] for each segment start, in order.
var events: Array[Vector2i] = []

## Plays the line's recorded words (vocabulary), if it has any.
var _words: BlabberWordPlayer
var _mixed := 0


## Picks the right engine for a voice: samples if it has any, else the synth.
static func create(p_segments: Array, p_voice: BlabberVoice, p_sample_rate: float) -> BlabberEngine:
	if p_voice.sample_bank != null and p_voice.sample_bank.active_count() > 0:
		return BlabberSampler.new(p_segments, p_voice, p_sample_rate)
	return BlabberSynth.new(p_segments, p_voice, p_sample_rate)


## Renders the next `frames` mono samples. After the end it returns silence.
func render(frames: int) -> PackedFloat32Array:
	var out := _render(frames)
	if _words:
		_words.mix(out, _mixed)
	_mixed += frames
	return out


## Renders the whole line at once (for baking to a file).
func render_all() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	while not finished:
		out.append_array(render(4096))
	out.resize(end_sample)
	return out


## Mouth openness 0..1 at a sample position.
func mouth_at(sample_pos: int) -> float:
	if _words:
		var m := _words.mouth_at(sample_pos)
		if m >= 0.0:
			return m
	return _mouth_at(sample_pos)


# --- For the engines ------------------------------------------------------------

## Renders the voice itself (without recorded words).
func _render(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	return out


func _mouth_at(_sample_pos: int) -> float:
	return 0.0


## Call at the end of _init. block: the engine moves to the next segment only
## every this many samples.
func _start_words(block := 1) -> void:
	_words = BlabberWordPlayer.make(segments, voice, sample_rate, block)
