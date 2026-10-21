class_name BlabberSynth
extends BlabberEngine
## Real-time formant voice synthesizer.
##
## Sound path: glottal pulse (the buzz) + breath noise -> 4 formant
## resonators (the throat shape) + filtered hiss for consonants ->
## growl / ring mod -> output. Parameters glide smoothly between segments,
## so sounds blend into each other like real speech.

const BLOCK := 32 ## Samples per control update.
const BW_BASE := [60.0, 90.0, 150.0, 200.0] ## Formant bandwidths, Hz.
const CASCADE_GAIN := 0.28
const FRIC_GAIN := 0.55
const ASP_GAIN := 0.35
const PRESENCE := 0.4

## Mouth openness (0..1) for each BLOCK of rendered audio.
var mouth_track := PackedFloat32Array()

var _buf := PackedFloat32Array()
var _buf_pos := BLOCK
var _block_index := 0
var _seg_i := -1
var _seg_pos := 0
var _seg_len := 0
var _seg: Dictionary

# Smoothed control values.
var _v := 0.0
var _vo := 1.0
var _asp := 0.0
var _fr := 0.0
var _nf := 3000.0
var _nq := 1.0
var _amp := 0.0
var _f1 := 500.0
var _f2 := 1500.0
var _f3 := 2500.0
var _f4 := 3500.0
var _f0 := 120.0
var _br := 0.0
var _ro := 0.0
var _gr := 0.0
var _te := 0.5
var _ji := 0.0
var _vd := 0.0
var _vr := 5.5
var _mouth := 0.0

var _k_fast := 0.0
var _k_amp := 0.0
var _k_form := 0.0
var _k_pitch := 0.0
var _k_slow := 0.0
var _k_mouth := 0.0

# Audio state.
var _rng := 22222
var _phase := 0.0
var _prev_flow := 0.0
var _period_scale := 1.0
var _period_amp := 1.0
var _alt := false
var _tilt := 0.0
var _r1a := 0.0
var _r1b := 0.0
var _r2a := 0.0
var _r2b := 0.0
var _r3a := 0.0
var _r3b := 0.0
var _r4a := 0.0
var _r4b := 0.0
var _nx1 := 0.0
var _nx2 := 0.0
var _ny1 := 0.0
var _ny2 := 0.0
var _mx1 := 0.0
var _mx2 := 0.0
var _my1 := 0.0
var _my2 := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _pre := 0.0
var _dcx := 0.0
var _dcy := 0.0
var _vib_ph := 0.0
var _drift_ph := 0.0
var _growl_ph := 0.0
var _ring_ph := 0.0


func _init(p_segments: Array, p_voice: BlabberVoice, p_sample_rate: float = 22050.0) -> void:
	segments = p_segments
	voice = p_voice
	sample_rate = p_sample_rate
	_buf.resize(BLOCK)
	var block_s := BLOCK / sample_rate
	_k_fast = 1.0 - exp(-block_s / 0.003)
	_k_amp = 1.0 - exp(-block_s / 0.010)
	_k_form = 1.0 - exp(-block_s / 0.018)
	_k_pitch = 1.0 - exp(-block_s / 0.035)
	_k_slow = 1.0 - exp(-block_s / 0.060)
	_k_mouth = 1.0 - exp(-block_s / 0.030)
	_rng = (hash(str(segments.size())) & 0x7fffffff) | 1
	if not segments.is_empty():
		var s0: Dictionary = segments[0]
		var first_voiced := s0
		for s in segments:
			if s.v > 0.0:
				first_voiced = s
				break
		_f0 = first_voiced.p0
		_f1 = first_voiced.f[0]; _f2 = first_voiced.f[1]; _f3 = first_voiced.f[2]; _f4 = first_voiced.f[3]
		_te = first_voiced.te; _br = first_voiced.br; _ro = first_voiced.ro; _gr = first_voiced.gr
		_ji = first_voiced.ji; _vd = first_voiced.vd; _vr = first_voiced.vr; _vo = first_voiced.vo


## Renders the next `frames` mono samples. After the end it returns silence.
func render(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var i := 0
	while i < frames:
		if _buf_pos >= BLOCK:
			_render_block()
			_buf_pos = 0
		var take := mini(BLOCK - _buf_pos, frames - i)
		for k in take:
			out[i + k] = _buf[_buf_pos + k]
		i += take
		_buf_pos += take
	return out


func mouth_at(sample_pos: int) -> float:
	var i := sample_pos / BLOCK
	if i < 0 or i >= mouth_track.size():
		return 0.0
	return mouth_track[i]


static func _reso(freq: float, bw: float, sr: float) -> Vector3:
	var r := exp(-PI * bw / sr)
	var c := -r * r
	var b := 2.0 * r * cos(TAU * freq / sr)
	return Vector3(1.0 - b - c, b, c)


func _render_block() -> void:
	var pos := _block_index * BLOCK
	_block_index += 1
	if not finished:
		while _seg_pos >= _seg_len:
			_seg_i += 1
			if _seg_i >= segments.size():
				finished = true
				end_sample = pos
				break
			_seg = segments[_seg_i]
			_seg_len = maxi(1, int(float(_seg.d) * sample_rate))
			_seg_pos = 0
			events.append(Vector2i(pos, _seg_i))
	if finished:
		_buf.fill(0.0)
		mouth_track.append(0.0)
		return

	var sr := sample_rate
	var sg := _seg
	var t := float(_seg_pos) / float(_seg_len)
	_seg_pos += BLOCK

	# Glide controls toward this segment's targets.
	var ka := _k_fast if sg.fast else _k_amp
	_v += (sg.v - _v) * ka
	_asp += (sg.asp - _asp) * ka
	_fr += (sg.fr - _fr) * ka
	if sg.fr > 0.0:
		_nf = sg.nf
		_nq = sg.nq
	_amp += (sg.a - _amp) * _k_amp
	var f: Array = sg.f
	_f1 += (f[0] - _f1) * _k_form
	_f2 += (f[1] - _f2) * _k_form
	_f3 += (f[2] - _f3) * _k_form
	_f4 += (f[3] - _f4) * _k_form
	_f0 += (lerpf(sg.p0, sg.p1, t) - _f0) * _k_pitch
	_vo += (sg.vo - _vo) * _k_slow
	_br += (sg.br - _br) * _k_slow
	_ro += (sg.ro - _ro) * _k_slow
	_gr += (sg.gr - _gr) * _k_slow
	_te += (sg.te - _te) * _k_slow
	_ji += (sg.ji - _ji) * _k_slow
	_vd += (sg.vd - _vd) * _k_slow
	_vr = sg.vr
	_mouth += (sg.m * clampf((_v + _asp) * minf(_amp, 1.0), 0.0, 1.0) - _mouth) * _k_mouth
	mouth_track.append(_mouth)

	# Pitch with vibrato and slow natural drift.
	var block_s := BLOCK / sr
	_vib_ph = fmod(_vib_ph + TAU * _vr * block_s, TAU)
	_drift_ph = fmod(_drift_ph + TAU * 1.3 * block_s, TAU * 100.0)
	var semis := _vd * sin(_vib_ph) + 0.12 * sin(_drift_ph) + 0.08 * sin(_drift_ph * 2.37)
	var f0 := clampf(_f0 * pow(2.0, semis / 12.0), 20.0, sr * 0.2)
	var inc := f0 / sr

	# Glottal pulse shape: tense voices close faster and sound brighter.
	var oq := lerpf(0.8, 0.45, _te)
	var tp := oq * 0.6
	var inv_tp := 1.0 / tp
	var inv_tn := 1.0 / (oq - tp)
	var dnorm := 0.1 / inc
	var tilt_k := lerpf(0.3, 1.0, _te)

	# Throat resonances.
	var fs := voice.formant_scale
	var lim := sr * 0.45
	var bwm := 0.7 + 0.3 * fs
	var c1 := _reso(minf(_f1 * fs, lim), BW_BASE[0] * bwm, sr)
	var c2 := _reso(minf(_f2 * fs, lim), BW_BASE[1] * bwm, sr)
	var c3 := _reso(minf(_f3 * fs, lim), BW_BASE[2] * bwm, sr)
	var c4 := _reso(minf(_f4 * fs, lim), BW_BASE[3] * bwm, sr)

	# Hiss filter (band-pass) for consonants.
	var w0 := TAU * minf(_nf * sqrt(fs), lim) / sr
	var alpha := sin(w0) / (2.0 * _nq)
	var na0 := 1.0 + alpha
	var nb0 := alpha / na0
	var na1 := -2.0 * cos(w0) / na0
	var na2 := (1.0 - alpha) / na0
	# Wide filters pass more energy; keep loudness steady across sounds.
	var fric_norm := sqrt(_nq)

	# Growl: fast rumble that pulses the loudness, then drive.
	_growl_ph = fmod(_growl_ph + TAU * (28.0 + 9.0 * sin(_drift_ph * 3.1)) * block_s, TAU)
	var growl_am := 1.0 - _gr * 0.45 * (1.0 + sin(_growl_ph))
	var drive := 1.0 + _gr * 2.5
	var drive_norm := 1.0 / (1.0 + _gr * 0.8)
	var growl_lp := 1.0 - exp(-TAU * lerpf(9000.0, 2600.0, _gr) / sr)

	# High voices have more pulses per second, so they get a little quieter.
	var pitch_comp := clampf(pow(120.0 / f0, 0.4), 0.3, 2.0)
	var voiced_amt := _v * _vo * (1.0 - _br * 0.5) * pitch_comp
	var breath_amt := (_asp + _br * _v * 0.7) * ASP_GAIN
	var fric_amt := _fr * FRIC_GAIN
	var amp := _amp * voice.volume * growl_am
	var ro := _ro
	var ji := _ji
	var shim := voice.shimmer
	var ring_inc := voice.ring_mod_hz / sr
	var ring_mix := voice.ring_mod_mix if voice.ring_mod_hz > 0.0 else 0.0

	# Locals for the sample loop (much faster than member access).
	var rng := _rng
	var phase := _phase
	var prev_flow := _prev_flow
	var pscale := _period_scale
	var pamp := _period_amp
	var alt := _alt
	var tilt := _tilt
	var r1a := _r1a; var r1b := _r1b
	var r2a := _r2a; var r2b := _r2b
	var r3a := _r3a; var r3b := _r3b
	var r4a := _r4a; var r4b := _r4b
	var nx1 := _nx1; var nx2 := _nx2; var ny1 := _ny1; var ny2 := _ny2
	var mx1 := _mx1; var mx2 := _mx2; var my1 := _my1; var my2 := _my2
	var lp := _lp
	var lp2 := _lp2
	var pre := _pre
	var pre_k := PRESENCE * (1.0 - _gr)
	var dcx := _dcx; var dcy := _dcy
	var ring_ph := _ring_ph
	var a1 := c1.x; var b1 := c1.y; var cc1 := c1.z
	var a2 := c2.x; var b2 := c2.y; var cc2 := c2.z
	var a3 := c3.x; var b3 := c3.y; var cc3 := c3.z
	var a4 := c4.x; var b4 := c4.y; var cc4 := c4.z
	var gr := _gr

	for s in BLOCK:
		rng = (rng * 1103515245 + 12345) & 0x7fffffff
		var nz := float(rng) / 1073741823.5 - 1.0

		phase += inc * pscale
		if phase >= 1.0:
			phase -= 1.0
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var r1 := float(rng) / 2147483647.0
			rng = (rng * 1103515245 + 12345) & 0x7fffffff
			var r2 := float(rng) / 2147483647.0
			pscale = 1.0 + (r1 * 2.0 - 1.0) * ji
			pamp = 1.0 - r2 * shim
			alt = not alt
			if alt and ro > 0.0:
				# Every other cycle weaker and longer = rasp / vocal fry.
				pamp *= 1.0 - ro * 0.65
				pscale /= 1.0 + ro * 0.25

		var flow := 0.0
		if phase < tp:
			var x := phase * inv_tp
			flow = x * x * (3.0 - 2.0 * x)
		elif phase < oq:
			var x := (phase - tp) * inv_tn
			flow = 1.0 - x * x
		var src := (flow - prev_flow) * dnorm * voiced_amt * pamp
		prev_flow = flow
		tilt += (src - tilt) * tilt_k
		var exc := tilt + nz * breath_amt * (0.4 + 0.6 * flow)

		var y := a1 * exc + b1 * r1a + cc1 * r1b
		r1b = r1a; r1a = y
		y = a2 * y + b2 * r2a + cc2 * r2b
		r2b = r2a; r2a = y
		y = a3 * y + b3 * r3a + cc3 * r3b
		r3b = r3a; r3a = y
		y = a4 * y + b4 * r4a + cc4 * r4b
		r4b = r4a; r4a = y

		# Two band-pass stages in a row give a focused hiss.
		var fx := nz * fric_amt
		var fm := nb0 * fx - nb0 * nx2 - na1 * ny1 - na2 * ny2
		nx2 = nx1; nx1 = fx; ny2 = ny1; ny1 = fm
		var fy := nb0 * fm - nb0 * mx2 - na1 * my1 - na2 * my2
		mx2 = mx1; mx1 = fm; my2 = my1; my1 = fy
		fy *= fric_norm

		# Treble lift for clarity, then add the hiss.
		var yv := y * CASCADE_GAIN
		var o := (yv + pre_k * (yv - pre) + fy) * amp
		pre = yv
		if ring_mix > 0.0:
			ring_ph += ring_inc
			if ring_ph >= 1.0:
				ring_ph -= 1.0
			var tri := 4.0 * absf(ring_ph - 0.5) - 1.0
			o = o * (1.0 - ring_mix) + o * tri * ring_mix * 1.6
		if gr > 0.01:
			o = tanh(o * drive) * drive_norm
			# Keep the rumble, lose the fizz the distortion adds.
			lp += (o - lp) * growl_lp
			lp2 += (lp - lp2) * growl_lp
			o = lp2
		# Remove DC offset.
		var dc := o - dcx + 0.995 * dcy
		dcx = o; dcy = dc
		# Soft limiter so shouting never hard-clips.
		var mag := absf(dc)
		if mag > 0.7:
			dc = signf(dc) * (0.7 + 0.3 * tanh((mag - 0.7) / 0.3))
		_buf[s] = dc

	_rng = rng
	_phase = phase
	_prev_flow = prev_flow
	_period_scale = pscale
	_period_amp = pamp
	_alt = alt
	_tilt = tilt
	_r1a = r1a; _r1b = r1b; _r2a = r2a; _r2b = r2b
	_r3a = r3a; _r3b = r3b; _r4a = r4a; _r4b = r4b
	_nx1 = nx1; _nx2 = nx2; _ny1 = ny1; _ny2 = ny2
	_mx1 = mx1; _mx2 = mx2; _my1 = my1; _my2 = my2
	_lp = lp
	_lp2 = lp2
	_pre = pre
	_dcx = dcx; _dcy = dcy
	_ring_ph = ring_ph
