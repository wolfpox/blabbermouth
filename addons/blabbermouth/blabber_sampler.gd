class_name BlabberSampler
extends BlabberEngine
## Speaks a line using syllables from a recording (BlabberSampleBank).
##
## Each syllable in the text picks a recorded syllable with a similar
## brightness (so "ee" words get bright slices and "oo" words get dark ones).
## The same word always picks the same slices. Each slice is then re-pitched
## to follow the sentence melody and resized with PSOLA, so pitch and
## throat size change separately without the chipmunk effect.

## Vowel brightness targets, 0 = darkest ("o") .. 1 = brightest ("i").
const VOWEL_BRIGHTNESS := {
	"i": 1.0, "ih": 0.8, "e": 0.69, "ae": 0.61, "er": 0.35, "uh": 0.24, "a": 0.17, "u": 0.02, "o": 0.0,
}
const UNPITCHED_GRAIN := 0.009 ## Grain size for unpitched sounds, seconds.
const GAIN := 0.55 ## Matches the loudness of synth voices.

var bank: BlabberSampleBank

var _src := PackedFloat32Array()
var _scale := 1.0 ## Bank samples -> output samples.
var _out := PackedFloat32Array()
var _syls: Array = []
var _next_syl := 0
var _pos := 0
var _ranks := {}
var _active: Array = []


func _init(p_segments: Array, p_voice: BlabberVoice, p_sample_rate: float = 22050.0) -> void:
	segments = p_segments
	voice = p_voice
	sample_rate = p_sample_rate
	bank = voice.sample_bank
	_src = bank.audio_at(int(sample_rate))
	_scale = sample_rate / bank.sample_rate
	_rank_slices()
	_plan()
	_start_words()


## Brightness rank 0..1 of each active slice among the others.
func _rank_slices() -> void:
	for i in bank.slice_count():
		if bank.slice_enabled[i]:
			_active.append(i)
	var by_b := _active.duplicate()
	by_b.sort_custom(func(x, y): return bank.slice_brightness[x] < bank.slice_brightness[y])
	for r in by_b.size():
		_ranks[by_b[r]] = float(r) / maxf(1.0, by_b.size() - 1.0)


## Groups segments into syllables (onset consonants + vowel + coda).
func _plan() -> void:
	var t := 0
	var cur = null
	var pending := -1
	var word := ""
	var k := 0
	var last_pick := -1
	var tail := 0
	for i in segments.size():
		var sg: Dictionary = segments[i]
		events.append(Vector2i(t, i))
		var n := maxi(1, int(float(sg.d) * sample_rate))
		var silent: bool = sg.v == 0.0 and sg.asp == 0.0 and sg.fr == 0.0 and sg.m == 0.0
		if sg.word != "":
			word = sg.word
			k = 0
		if silent:
			if cur != null:
				cur.end = t
				cur = null
			pending = -1
		else:
			if sg.syl:
				var st := pending if pending >= 0 else t
				if cur != null:
					cur.end = st
				cur = {"start": st, "end": -1, "p0": sg.p0, "p1": sg.p1, "a": sg.a, "ph": sg.ph, "word": word, "k": k}
				_syls.append(cur)
				k += 1
				pending = -1
			elif pending < 0 and not VOWEL_BRIGHTNESS.has(sg.ph):
				pending = t
		t += n
	if cur != null:
		cur.end = t
	# Choose a slice and output length for each syllable.
	for sy in _syls:
		var pick := _choose(sy, last_pick)
		last_pick = pick
		sy.slice = pick
		var s_len := (bank.slice_ends[pick] - bank.slice_starts[pick]) * _scale
		var span: float = sy.end - sy.start
		var stretch := clampf(span / s_len, 0.65, 1.6)
		sy.stretch = stretch
		sy.len = minf(s_len * stretch, span + 0.04 * sample_rate)
		tail = maxi(tail, int(sy.start + sy.len + 0.05 * sample_rate))
	end_sample = maxi(t, tail)
	_out.resize(end_sample + int(0.1 * sample_rate))


func _choose(sy: Dictionary, last_pick: int) -> int:
	var target: float = VOWEL_BRIGHTNESS.get(sy.ph, 0.5)
	var cands := _active.duplicate()
	cands.sort_custom(func(x, y): return absf(_ranks[x] - target) < absf(_ranks[y] - target))
	var n := mini(voice.sample_variety, cands.size())
	var h := absi(hash("%s:%d:%d" % [String(sy.word).to_lower(), sy.k, voice.language_seed]))
	var pick: int = cands[h % n]
	if pick == last_pick and n > 1:
		pick = cands[(h + 1) % n]
	return pick


func _render(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var until := _pos + frames
	while _next_syl < _syls.size() and _syls[_next_syl].start < until:
		_render_syllable(_syls[_next_syl])
		_next_syl += 1
	for i in frames:
		var p := _pos + i
		if p >= end_sample:
			break
		var v := _out[p]
		var mag := absf(v)
		if mag > 0.7:
			v = signf(v) * (0.7 + 0.3 * tanh((mag - 0.7) / 0.3))
		out[i] = v
	_pos = until
	if _pos >= end_sample:
		finished = true
	return out


func _mouth_at(sample_pos: int) -> float:
	var a := maxi(0, sample_pos - 128)
	var b := mini(_out.size(), sample_pos + 128)
	if b <= a:
		return 0.0
	var s := 0.0
	for i in range(a, b):
		s += _out[i] * _out[i]
	return clampf(sqrt(s / (b - a)) * 6.0, 0.0, 1.0)


## Overlap-adds pitch-synchronous grains of one slice into the output.
func _render_syllable(sy: Dictionary) -> void:
	var idx: int = sy.slice
	var s_start := bank.slice_starts[idx] * _scale
	var s_end := bank.slice_ends[idx] * _scale
	var f_src := bank.slice_pitch[idx]
	var pitched := f_src > 0.0
	var ref := bank.reference_pitch()
	var melody := voice.sample_melody
	var fs := voice.formant_scale
	var stretch: float = sy.stretch
	var out_len: float = sy.len
	var start: int = sy.start
	var amp: float = sy.a * voice.volume * GAIN
	var att := 0.008 * sample_rate
	var rel := 0.02 * sample_rate
	var p_in := (sample_rate / f_src) if pitched else UNPITCHED_GRAIN * sample_rate
	var marks := _marks(s_start, s_end, p_in) if pitched else PackedFloat32Array()
	var src := _src
	var src_n := src.size()
	var out := _out
	var out_n := out.size()
	var mi := 0
	var t_out := 0.0
	while t_out < out_len:
		var u := t_out / out_len
		var f_t := lerpf(sy.p0, sy.p1, u)
		var ratio: float
		var hop: float
		var read: float
		var center: float
		var t_in := s_start + t_out / stretch
		if pitched:
			# Blend between the line's melody and the recording's own pitch.
			ratio = pow(f_t / f_src, melody) * pow(voice.pitch / ref, 1.0 - melody)
			hop = p_in / ratio
			read = fs
			while mi + 1 < marks.size() and absf(marks[mi + 1] - t_in) <= absf(marks[mi] - t_in):
				mi += 1
			center = marks[mi]
		else:
			# No clear pitch: shift everything together, grains at 50% overlap.
			ratio = f_t / ref
			read = fs * ratio
			hop = p_in / read
			center = t_in
		var hw := p_in / read
		var env := minf(1.0, t_out / att) * minf(1.0, (out_len - t_out) / rel)
		var g := amp * maxf(env, 0.0)
		var oc := start + int(t_out)
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
		t_out += hop
	_out = out


## Pitch marks: one per cycle, snapped to the strongest peak near each.
func _marks(a: float, b: float, period: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	var src := _src
	var n := src.size()
	var search := int(period * 0.3)
	var pos := a + period * 0.5
	while pos < b:
		var best := int(pos)
		var best_v := -1.0
		for i in range(int(pos) - search, int(pos) + search + 1):
			if i >= 0 and i < n and absf(src[i]) > best_v:
				best_v = absf(src[i])
				best = i
		if not m.is_empty() and best <= m[-1] + period * 0.5:
			best = int(m[-1] + period)
		m.append(best)
		pos = best + period
	if m.is_empty():
		m.append((a + b) * 0.5)
	return m
