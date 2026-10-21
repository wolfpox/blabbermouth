@tool
class_name BlabberSampleBank
extends Resource
## A recording cut into syllables, ready to be spoken by a BlabberVoice.
##
## Make one with BlabberSampleBank.from_samples() from any mono audio
## (a mic recording or an imported file). It cleans up the audio, finds the
## syllables, and measures the pitch and brightness of each.
## Save it with the voice as a .res file (binary keeps it small).

const RATE := 22050 ## All banks are stored at this rate.
const FRAME := 220 ## Analysis frame, 10 ms.
const MIN_FRAMES := 6 ## Shortest syllable, 60 ms.
const MAX_FRAMES := 45 ## Longest syllable, 450 ms.
const MAX_SECONDS := 30.0

@export var audio := PackedFloat32Array()
@export var sample_rate := RATE
## Syllable start and end, in samples.
@export var slice_starts := PackedInt32Array()
@export var slice_ends := PackedInt32Array()
## Pitch of each syllable in Hz. 0 = no clear pitch (a hiss, a click, a bark).
@export var slice_pitch := PackedFloat32Array()
## Higher = brighter ("ee"), lower = darker ("oo"). Only the order matters.
@export var slice_brightness := PackedFloat32Array()
## 1 = used, 0 = removed by the user.
@export var slice_enabled := PackedByteArray()
## Typical pitch of the recording in Hz (0 if none was found).
@export var base_pitch := 0.0
## How eagerly the audio is cut into syllables. Higher = more, smaller pieces.
@export_range(0.0, 1.0, 0.01) var sensitivity := 0.5

var _resampled := {}


## Cleans up mono audio at any sample rate, then finds syllables.
static func from_samples(samples: PackedFloat32Array, rate: int, p_sensitivity := 0.5) -> BlabberSampleBank:
	var b := BlabberSampleBank.new()
	b.audio = prepare(samples, rate)
	b.sensitivity = p_sensitivity
	b.analyze()
	return b


func slice_count() -> int:
	return slice_starts.size()


func active_count() -> int:
	var n := 0
	for e in slice_enabled:
		n += e
	return n


func set_slice_enabled(i: int, on: bool) -> void:
	slice_enabled[i] = 1 if on else 0
	_update_base_pitch()
	emit_changed()


## Typical pitch to use as a voice's pitch (falls back to 200 Hz).
func reference_pitch() -> float:
	return base_pitch if base_pitch > 0.0 else 200.0


## One syllable as a playable stream, for previewing.
func slice_stream(i: int) -> AudioStreamWAV:
	var a := slice_starts[i]
	var b := slice_ends[i]
	var data := PackedByteArray()
	data.resize((b - a) * 2)
	for k in b - a:
		data.encode_s16(k * 2, int(clampf(audio[a + k], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav


## The audio at another sample rate (cached). Used by the sampler.
func audio_at(rate: int) -> PackedFloat32Array:
	if rate == sample_rate:
		return audio
	if not _resampled.has(rate):
		_resampled[rate] = resample(audio, sample_rate, rate)
	return _resampled[rate]


# --- Clean-up -------------------------------------------------------------------

## Resample, remove rumble, trim silence and even out the volume.
static func prepare(samples: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var x := samples
	if x.size() > int(MAX_SECONDS * rate):
		x = x.slice(0, int(MAX_SECONDS * rate))
	if rate != RATE:
		x = resample(x, rate, RATE)
	# High-pass at ~50 Hz removes DC and handling rumble.
	var hp := PackedFloat32Array()
	hp.resize(x.size())
	var k := exp(-TAU * 50.0 / RATE)
	var px := 0.0
	var py := 0.0
	for i in x.size():
		py = k * (py + x[i] - px)
		px = x[i]
		hp[i] = py
	# Trim quiet start and end (below -40 dB of the peak).
	var peak := 0.0
	for v in hp:
		peak = maxf(peak, absf(v))
	if peak < 1e-4:
		return PackedFloat32Array()
	var env := _envelope(hp)
	var thr := peak * 0.01
	var first := 0
	while first < env.size() and env[first] < thr:
		first += 1
	var last := env.size() - 1
	while last > first and env[last] < thr:
		last -= 1
	var a := maxi(0, (first - 2) * FRAME)
	var b := mini(hp.size(), (last + 3) * FRAME)
	var out := hp.slice(a, b)
	_gate(out, env.slice(a / FRAME, b / FRAME + 1))
	var g := 0.9 / peak
	for i in out.size():
		out[i] *= g
	return out


## Fades out room noise between sounds, so it isn't repeated in every syllable.
static func _gate(x: PackedFloat32Array, env: PackedFloat32Array) -> void:
	if env.size() < 4:
		return
	var sorted := Array(env)
	sorted.sort()
	var noise: float = maxf(sorted[int(sorted.size() * 0.1)], 1e-6)
	var gains := PackedFloat32Array()
	gains.resize(env.size())
	var g := 0.0
	for f in env.size():
		var target := smoothstep(noise * 2.0, noise * 5.0, env[f])
		# Open fast, close slowly.
		g = target if target > g else lerpf(g, target, 0.3)
		gains[f] = g
	for i in x.size():
		var fp := float(i) / FRAME - 0.5
		var f0 := clampi(int(fp), 0, gains.size() - 1)
		var f1 := mini(f0 + 1, gains.size() - 1)
		x[i] *= lerpf(gains[f0], gains[f1], clampf(fp - f0, 0.0, 1.0))


## Linear resampling, with a gentle low-pass first when shrinking.
static func resample(x: PackedFloat32Array, from_rate: int, to_rate: int) -> PackedFloat32Array:
	var src := x
	if to_rate < from_rate:
		src = x.duplicate()
		var c := 1.0 - exp(-TAU * 0.45 * to_rate / from_rate)
		for pass_i in 2:
			var y := 0.0
			for i in src.size():
				y += (src[i] - y) * c
				src[i] = y
	var ratio := float(from_rate) / to_rate
	var n := int(src.size() / ratio)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var p := i * ratio
		var i0 := int(p)
		var f := p - i0
		var a := src[i0]
		var b := src[mini(i0 + 1, src.size() - 1)]
		out[i] = a + (b - a) * f
	return out


static func _envelope(x: PackedFloat32Array) -> PackedFloat32Array:
	var n := x.size() / FRAME
	var env := PackedFloat32Array()
	env.resize(n)
	for f in n:
		var s := 0.0
		var o := f * FRAME
		for i in FRAME:
			var v := x[o + i]
			s += v * v
		env[f] = sqrt(s / FRAME)
	return env


# --- Syllable finding -------------------------------------------------------------

## Finds syllables. Call again after changing sensitivity.
func analyze() -> void:
	slice_starts = PackedInt32Array()
	slice_ends = PackedInt32Array()
	slice_pitch = PackedFloat32Array()
	slice_brightness = PackedFloat32Array()
	slice_enabled = PackedByteArray()
	if audio.size() < FRAME * MIN_FRAMES:
		base_pitch = 0.0
		emit_changed()
		return
	var env := _envelope(audio)
	# Smooth over 30 ms.
	var sm := env.duplicate()
	for i in range(1, env.size() - 1):
		sm[i] = (env[i - 1] + env[i] + env[i + 1]) / 3.0
	var sorted := Array(sm)
	sorted.sort()
	var floor_v: float = sorted[int(sorted.size() * 0.1)]
	var peak: float = sorted[-1]
	var thr := floor_v + (peak - floor_v) * lerpf(0.25, 0.04, sensitivity)
	var dip := lerpf(0.45, 0.85, sensitivity)

	# Loud regions, with tiny gaps merged.
	var regions: Array = []
	var start := -1
	var quiet := 0
	for i in sm.size():
		if sm[i] > thr:
			if start < 0:
				start = i
			quiet = 0
		elif start >= 0:
			quiet += 1
			if quiet > 3:
				regions.append(Vector2i(start, i - quiet + 1))
				start = -1
				quiet = 0
	if start >= 0:
		regions.append(Vector2i(start, sm.size()))

	for r in regions:
		if r.y - r.x < MIN_FRAMES - 1:
			continue
		for piece in _split(sm, r.x, r.y, dip):
			_add_slice(piece.x, piece.y)
	_update_base_pitch()
	emit_changed()


## Splits a loud region at volume dips between syllables.
func _split(sm: PackedFloat32Array, a: int, b: int, dip: float) -> Array:
	if b - a < MIN_FRAMES * 2:
		return [Vector2i(a, b)]
	var best := -1
	var best_score := dip
	for m in range(a + MIN_FRAMES, b - MIN_FRAMES):
		if sm[m] > sm[m - 1] or sm[m] > sm[m + 1]:
			continue
		var left := 0.0
		for i in range(a, m):
			left = maxf(left, sm[i])
		var right := 0.0
		for i in range(m, b):
			right = maxf(right, sm[i])
		var score := sm[m] / maxf(minf(left, right), 1e-9)
		if score < best_score:
			best_score = score
			best = m
	if best < 0 and b - a > MAX_FRAMES:
		# Too long and no clear dip: cut at the quietest point in the middle.
		var lo := INF
		for m in range(a + MIN_FRAMES, b - MIN_FRAMES):
			if sm[m] < lo:
				lo = sm[m]
				best = m
	if best < 0:
		return [Vector2i(a, b)]
	return _split(sm, a, best, dip) + _split(sm, best, b, dip)


func _add_slice(fa: int, fb: int) -> void:
	var a := fa * FRAME
	var b := mini(fb * FRAME + FRAME, audio.size())
	slice_starts.append(a)
	slice_ends.append(b)
	slice_pitch.append(_detect_pitch(a, b))
	slice_brightness.append(_brightness(a, b))
	slice_enabled.append(1)


func _update_base_pitch() -> void:
	var ps: Array = []
	for i in slice_pitch.size():
		if slice_enabled[i] and slice_pitch[i] > 0.0:
			ps.append(slice_pitch[i])
	ps.sort()
	base_pitch = ps[ps.size() / 2] if not ps.is_empty() else 0.0


# --- Measurements -----------------------------------------------------------------

## Brightness: energy around 2.3 kHz versus around 1.1 kHz, measured on the
## loudest (vowel) part. This tracks the second formant, which is what makes
## "ee" sound bright and "oo" sound dark.
func _brightness(a: int, b: int) -> float:
	var n_frames := (b - a) / FRAME
	if n_frames < 1:
		return 0.0
	var env := PackedFloat32Array()
	env.resize(n_frames)
	var top := 0.0
	for f in n_frames:
		var s := 0.0
		for i in FRAME:
			var v := audio[a + f * FRAME + i]
			s += v * v
		env[f] = s
		top = maxf(top, s)
	var hi := _Band.new(2300.0, 1.3)
	var lo := _Band.new(1100.0, 2.0)
	var e_hi := 0.0
	var e_lo := 0.0
	for f in n_frames:
		var core := env[f] >= top * 0.3
		for i in FRAME:
			var v := audio[a + f * FRAME + i]
			var h := hi.run(v)
			var l := lo.run(v)
			if core:
				e_hi += h * h
				e_lo += l * l
	return log(maxf(e_hi, 1e-12) / maxf(e_lo, 1e-12))


class _Band:
	var b0: float
	var a1: float
	var a2: float
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(freq: float, q: float) -> void:
		var w := TAU * freq / RATE
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func run(x: float) -> float:
		var y := b0 * x - b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		return y


## Pitch from autocorrelation on a few frames near the middle (McLeod-style).
func _detect_pitch(a: int, b: int) -> float:
	# Work at half rate for speed.
	var sr := RATE / 2.0
	var lag_min := int(sr / 1000.0)
	var lag_max := int(sr / 55.0)
	var win := 256
	var need := (win + lag_max) * 2
	var found: Array = []
	var frames := 0
	for pos in [0.3, 0.5, 0.7]:
		var c := int(lerpf(a, b, pos))
		var s0 := c - need / 2
		if s0 < a - need / 4 or s0 + need > audio.size() or s0 < 0:
			continue
		frames += 1
		var x := PackedFloat32Array()
		x.resize(win + lag_max)
		for i in x.size():
			x[i] = (audio[s0 + i * 2] + audio[s0 + i * 2 + 1]) * 0.5
		var nsdf := PackedFloat32Array()
		nsdf.resize(lag_max + 1)
		var top := 0.0
		for lag in range(lag_min, lag_max + 1):
			var r := 0.0
			var m := 0.0
			for i in win:
				var p := x[i]
				var q := x[i + lag]
				r += p * q
				m += p * p + q * q
			var v := 2.0 * r / maxf(m, 1e-9)
			nsdf[lag] = v
			top = maxf(top, v)
		if top < 0.6:
			continue
		# First strong peak avoids octave errors.
		for lag in range(lag_min + 1, lag_max):
			var v := nsdf[lag]
			if v >= top * 0.88 and v >= nsdf[lag - 1] and v >= nsdf[lag + 1]:
				var den := nsdf[lag - 1] - 2.0 * v + nsdf[lag + 1]
				var shift := 0.0 if absf(den) < 1e-9 else 0.5 * (nsdf[lag - 1] - nsdf[lag + 1]) / den
				found.append(sr / (lag + clampf(shift, -0.5, 0.5)))
				break
	if found.is_empty() or found.size() * 2 < frames:
		return 0.0
	found.sort()
	return found[found.size() / 2]
