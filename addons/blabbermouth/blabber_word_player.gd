class_name BlabberWordPlayer
extends RefCounted
## Plays the recorded words in a line (see BlabberVocabulary), for both
## engines. The parser leaves silent segments where a recorded word goes;
## this renders the word's take into that space and the engine mixes it in.
##
## Each take is re-pitched and stretched with PSOLA (pitch-synchronous
## overlap-add), the same way recorded voices are. It moves to the line's
## pitch (so it follows the character, the melody and effects) while
## keeping its own rise and fall, fits the word's duration (so speed tags
## work), and can be resized like a throat. On top of that: vibrato and
## shakiness (shiver), rasp and growl (jolt, gruff voices), whisper, and
## the robot's ring modulation.

const GAIN := BlabberSampler.GAIN
const LOOKAHEAD := 0.4 ## Seconds: words are rendered this far ahead.

var sample_rate := 22050.0
var voice: BlabberVoice
## {start, seg, buf} for each recorded word, in order.
var _words: Array = []
var _next := 0


## A player for the recorded words in these segments, or null if there are
## none. block: the engine moves between segments every this many samples.
static func make(segments: Array, p_voice: BlabberVoice, p_sample_rate: float, block := 1) -> BlabberWordPlayer:
	for sg in segments:
		if sg.has("clip"):
			return BlabberWordPlayer.new(segments, p_voice, p_sample_rate, block)
	return null


func _init(segments: Array, p_voice: BlabberVoice, p_sample_rate: float, block := 1) -> void:
	voice = p_voice
	sample_rate = p_sample_rate
	var t := 0
	for sg in segments:
		if sg.has("clip"):
			_words.append({"start": t, "seg": sg, "buf": PackedFloat32Array()})
		var n := maxi(1, int(float(sg.d) * sample_rate))
		if block > 1:
			n = ceili(float(n) / block) * block
		t += n


## Adds the recorded words into out, which starts at sample position pos.
func mix(out: PackedFloat32Array, pos: int) -> void:
	var until := pos + out.size()
	var ahead := until + int(LOOKAHEAD * sample_rate)
	while _next < _words.size() and _words[_next].start < ahead:
		_words[_next].buf = _render(_words[_next].seg)
		_next += 1
	for k in _next:
		var w: Dictionary = _words[k]
		var a: int = w.start
		var buf: PackedFloat32Array = w.buf
		if a >= until:
			break
		if a + buf.size() <= pos:
			continue
		for i in range(maxi(pos, a), mini(until, a + buf.size())):
			out[i - pos] += buf[i - a]


## Mouth openness while a recorded word plays, or -1 elsewhere.
func mouth_at(sample_pos: int) -> float:
	for k in _next:
		var w: Dictionary = _words[k]
		var a: int = w.start
		var buf: PackedFloat32Array = w.buf
		if sample_pos < a or sample_pos >= a + buf.size():
			continue
		var i0 := maxi(0, sample_pos - a - 128)
		var i1 := mini(buf.size(), sample_pos - a + 128)
		var s := 0.0
		for i in range(i0, i1):
			s += buf[i] * buf[i]
		return clampf(sqrt(s / maxf(1.0, i1 - i0)) * 6.0, 0.0, 1.0)
	return -1.0


## Typical throat size for a pitch: 1.0 for a man (~110 Hz), about 1.17 for
## a woman, more for children. Used to fit a take to a voice.
static func natural_size(pitch_hz: float) -> float:
	if pitch_hz <= 0.0:
		return 1.0
	return clampf(pow(pitch_hz / 112.0, 0.24), 0.75, 1.6)


## The voice's throat size on the same scale (sample voices store it
## relative to their recording).
func _voice_size() -> float:
	var bank := voice.sample_bank
	if bank != null and bank.active_count() > 0:
		return voice.formant_scale * natural_size(bank.reference_pitch())
	return voice.formant_scale


func _render(sg: Dictionary) -> PackedFloat32Array:
	var clip: BlabberClip = sg.clip
	var data := clip.render_data(int(sample_rate))
	var src: PackedFloat32Array = data.audio
	var marks: PackedFloat32Array = data.marks
	var periods: PackedFloat32Array = data.periods
	var voiced: PackedByteArray = data.voiced
	var sr := sample_rate
	var out_len: float = float(sg.cd) * sr
	var out := PackedFloat32Array()
	if src.is_empty() or out_len < 1.0:
		return out
	out.resize(int(out_len) + int(0.03 * sr))
	var stretch := out_len / src.size()
	var fit: bool = sg.fit
	var f_clip := clip.pitch
	var pitched := f_clip > 0.0
	var vp := maxf(voice.pitch, 1.0)
	var pb: float = sg.pb
	var p0: float = sg.rp0
	var p1: float = sg.rp1
	var a0: float = sg.ra0
	var a1: float = sg.ra1
	var melody := voice.sample_melody
	# Fitted: the take moves to the voice's pitch and size and gets its rasp
	# and so on. Not fitted: only what the line adds on top of the voice.
	var anchor := vp if fit else f_clip
	var fs := clampf(_voice_size() / natural_size(f_clip), 0.5, 2.2) if fit else 1.0
	var ro: float = sg.ro if fit else maxf(sg.ro - voice.roughness, 0.0)
	var gr: float = sg.gr if fit else maxf(sg.gr - voice.growl, 0.0)
	var vd: float = sg.vd if fit else maxf(sg.vd - voice.vibrato_depth, 0.0)
	var vr: float = sg.vr
	var ji := maxf(float(sg.ji) - voice.jitter, 0.0) # A recording already wobbles naturally.
	var vo: float = sg.vo if fit else clampf(sg.vo + 1.0 - voice.voicing, 0.0, 1.0)
	var whisper := clampf(1.0 - vo, 0.0, 1.0)
	var amp := GAIN * voice.volume
	var att := 0.004 * sr
	var rel := 0.012 * sr
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(clip.audio.size()) ^ int(out_len)

	# Pass 1: pitch-synchronous grains (the voiced sound) and plain grains
	# (hiss and noise, which have no pitch to move).
	var t_out := 0.0
	var mi := 0
	var odd := false
	while t_out < out_len:
		var u := t_out / out_len
		var t_in := t_out / stretch
		while mi + 1 < marks.size() and absf(marks[mi + 1] - t_in) <= absf(marks[mi] - t_in):
			mi += 1
		var period := periods[mi]
		var target := lerpf(p0, p1, u)
		# The line's pitch tags and emotions in full; its melody as much as sample_melody says.
		var rel_pitch := (pb / vp) * pow(target / pb, melody)
		var env := minf(1.0, t_out / att) * minf(1.0, (out_len - t_out) / rel)
		var g := lerpf(a0, a1, u) * amp * maxf(env, 0.0)
		var hop: float
		var read: float
		if pitched and voiced[mi] == 1:
			var r := anchor * rel_pitch / f_clip
			if vd > 0.0:
				r *= pow(2.0, vd * sin(TAU * vr * t_out / sr) / 12.0)
			if ji > 0.0:
				r *= 1.0 + (rng.randf() * 2.0 - 1.0) * ji
			if ro > 0.0:
				# Every other cycle weaker and longer = rasp.
				odd = not odd
				if odd:
					g *= 1.0 - ro * 0.65
					r /= 1.0 + ro * 0.25
			r = clampf(r, 0.2, 8.0)
			read = fs
			hop = period / r
			# Denser grains add up louder; keep the level steady.
			g *= minf(1.0, pow(fs / r, 0.5)) * (1.0 - whisper)
		else:
			read = fs if pitched else fs * clampf(rel_pitch, 0.25, 4.0)
			hop = period / read
		_grain(out, int(t_out), src, marks[mi], period / read, read, g)
		t_out += hop

	# Pass 2, whisper: the same grains at random times, which keeps the
	# mouth shape but loses the pitch, like breath through the same throat.
	if whisper > 0.01 and pitched:
		t_out = 0.0
		mi = 0
		while t_out < out_len:
			var u := t_out / out_len
			var t_in := t_out / stretch
			while mi + 1 < marks.size() and absf(marks[mi + 1] - t_in) <= absf(marks[mi] - t_in):
				mi += 1
			var period := periods[mi]
			var hw := period / fs
			var hop := hw * lerpf(0.25, 0.75, rng.randf())
			if pitched and voiced[mi] == 1:
				var env := minf(1.0, t_out / att) * minf(1.0, (out_len - t_out) / rel)
				var g := lerpf(a0, a1, u) * amp * maxf(env, 0.0) * whisper * 0.55 * sqrt(hop / hw)
				if rng.randf() < 0.5:
					g = -g
				var center := marks[mi] + (rng.randf() * 2.0 - 1.0) * period
				_grain(out, int(t_out), src, center, hw, fs, g)
			t_out += hop

	_finish(out, gr)
	return out


## Adds one Hann-windowed grain of src, read around center at `read`
## samples per output sample, into out around position oc.
static func _grain(out: PackedFloat32Array, oc: int, src: PackedFloat32Array, center: float, hw: float, read: float, g: float) -> void:
	if g == 0.0 or hw < 1.0:
		return
	var out_n := out.size()
	var src_n := src.size()
	var k0 := -int(hw)
	for kk in range(k0, -k0 + 1):
		var o := oc + kk
		if o < 0 or o >= out_n:
			continue
		var sp := center + kk * read
		var i0 := int(sp)
		if i0 < 0 or i0 + 1 >= src_n:
			continue
		var fr := sp - i0
		var w := 0.5 + 0.5 * cos(PI * kk / hw)
		out[o] += w * g * (src[i0] + (src[i0 + 1] - src[i0]) * fr)


## Growl, the robot's ring modulation and a soft limiter, like the synth.
func _finish(out: PackedFloat32Array, gr: float) -> void:
	var sr := sample_rate
	var ring_mix := voice.ring_mod_mix if voice.ring_mod_hz > 0.0 else 0.0
	var ring_inc := voice.ring_mod_hz / sr
	var drive := 1.0 + gr * 2.5
	var drive_norm := 1.0 / (1.0 + gr * 0.8)
	var growl_lp := 1.0 - exp(-TAU * lerpf(9000.0, 2600.0, gr) / sr)
	var growl_ph := 0.0
	var ring_ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in out.size():
		var o := out[i]
		if gr > 0.01:
			growl_ph = fmod(growl_ph + TAU * 28.0 / sr, TAU)
			o *= 1.0 - gr * 0.45 * (1.0 + sin(growl_ph))
			o = tanh(o * drive) * drive_norm
			lp += (o - lp) * growl_lp
			lp2 += (lp - lp2) * growl_lp
			o = lp2
		if ring_mix > 0.0:
			ring_ph += ring_inc
			if ring_ph >= 1.0:
				ring_ph -= 1.0
			var tri := 4.0 * absf(ring_ph - 0.5) - 1.0
			o = o * (1.0 - ring_mix) + o * tri * ring_mix * 1.6
		var mag := absf(o)
		if mag > 0.7:
			o = signf(o) * (0.7 + 0.3 * tanh((mag - 0.7) / 0.3))
		out[i] = o
