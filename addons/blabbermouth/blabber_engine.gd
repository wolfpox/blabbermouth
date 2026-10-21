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


## Picks the right engine for a voice: samples if it has any, else the synth.
static func create(p_segments: Array, p_voice: BlabberVoice, p_sample_rate: float) -> BlabberEngine:
	if p_voice.sample_bank != null and p_voice.sample_bank.active_count() > 0:
		return BlabberSampler.new(p_segments, p_voice, p_sample_rate)
	return BlabberSynth.new(p_segments, p_voice, p_sample_rate)


## Renders the next `frames` mono samples. After the end it returns silence.
func render(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	return out


## Renders the whole line at once (for baking to a file).
func render_all() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	while not finished:
		out.append_array(render(4096))
	out.resize(end_sample)
	return out


## Mouth openness 0..1 at a sample position.
func mouth_at(_sample_pos: int) -> float:
	return 0.0
