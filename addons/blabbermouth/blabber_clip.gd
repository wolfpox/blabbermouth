@tool
class_name BlabberClip
extends Resource
## One recording ("take") of a word or phrase in a BlabberVocabulary.
##
## Make one with from_samples() from any mono audio. It is cleaned up like a
## recorded voice (rumble removed, silence trimmed, volume evened out) and
## its pitch is measured every 10 ms, so it can be moved to a character's
## pitch while keeping its own rise and fall.

const RATE := BlabberSampleBank.RATE ## All takes are stored at this rate.
const FRAME := 220 ## The pitch track has one value per 10 ms.
const MAX_SECONDS := 6.0

@export var audio := PackedFloat32Array()
@export var sample_rate := RATE
## Typical pitch in Hz. 0 = no clear pitch (a whisper, a click, a bark).
@export var pitch := 0.0
## Pitch every FRAME samples, in Hz. 0 where there's no clear pitch.
@export var pitch_track := PackedFloat32Array()

var _cache := {}


## Cleans up mono audio at any sample rate and measures its pitch.
## The result is empty (duration() == 0) if nothing could be heard.
static func from_samples(samples: PackedFloat32Array, rate: int) -> BlabberClip:
	var c := BlabberClip.new()
	var x := BlabberSampleBank.prepare(samples, rate)
	var most := int(MAX_SECONDS * RATE)
	if x.size() > most:
		x = x.slice(0, most)
		var fade := int(0.02 * RATE)
		for i in fade:
			x[most - 1 - i] *= float(i) / fade
	c.audio = x
	c.analyze()
	return c


func duration() -> float:
	return audio.size() / float(sample_rate)


## Measures the pitch track and the typical pitch. Call after changing audio.
func analyze() -> void:
	_cache.clear()
	var n := ceili(audio.size() / float(FRAME))
	pitch_track = PackedFloat32Array()
	pitch_track.resize(n)
	pitch = 0.0
	if n == 0:
		return
	# Quiet frames are breaths and gaps: no pitch there.
	var rms := PackedFloat32Array()
	rms.resize(n)
	var loudest := 0.0
	for f in n:
		var s := 0.0
		var a := f * FRAME
		var b := mini(a + FRAME, audio.size())
		for i in range(a, b):
			s += audio[i] * audio[i]
		rms[f] = sqrt(s / maxf(1.0, b - a))
		loudest = maxf(loudest, rms[f])
	var half := BlabberSampleBank.PITCH_SPAN / 2
	var raw := PackedFloat32Array()
	raw.resize(n)
	for f in n:
		if rms[f] < loudest * 0.08:
			continue
		var c := f * FRAME + FRAME / 2
		var s0 := clampi(c - half, 0, maxi(0, audio.size() - BlabberSampleBank.PITCH_SPAN))
		raw[f] = BlabberSampleBank.frame_pitch(audio, s0)
	# Readings far from the typical pitch are octave errors or noise.
	var found: Array = []
	for v in raw:
		if v > 0.0:
			found.append(v)
	if found.size() < 3:
		return
	found.sort()
	var typical: float = found[found.size() / 2]
	for f in n:
		if raw[f] < typical * 0.55 or raw[f] > typical * 1.8:
			raw[f] = 0.0
	# Median of three smooths the rest; lone pitched frames are dropped.
	var voiced: Array = []
	for f in n:
		var v := raw[f]
		if v <= 0.0:
			continue
		var trio := [v]
		if f > 0 and raw[f - 1] > 0.0:
			trio.append(raw[f - 1])
		if f + 1 < n and raw[f + 1] > 0.0:
			trio.append(raw[f + 1])
		if trio.size() == 1:
			continue
		trio.sort()
		pitch_track[f] = trio[trio.size() / 2] if trio.size() == 3 else (trio[0] + trio[1]) * 0.5
		voiced.append(pitch_track[f])
	if voiced.size() < 3:
		pitch_track.fill(0.0)
		return
	voiced.sort()
	pitch = voiced[voiced.size() / 2]


## Pitch in Hz at a sample position (in this clip's own rate), 0 if unvoiced.
func pitch_at(pos: float) -> float:
	var f := int(pos / FRAME)
	if f < 0 or f >= pitch_track.size():
		return 0.0
	return pitch_track[f]


## How loud each of `parts` equal pieces is, 0..1 (for drawing).
func levels(parts: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(parts, 1))
	var n := audio.size()
	if n == 0:
		return out
	var top := 1e-6
	for p in out.size():
		var a := n * p / out.size()
		var b := maxi(a + 1, n * (p + 1) / out.size())
		var s := 0.0
		for i in range(a, b):
			s += audio[i] * audio[i]
		out[p] = sqrt(s / (b - a))
		top = maxf(top, out[p])
	for p in out.size():
		out[p] /= top
	return out


## The take as recorded, for previewing.
func stream() -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(audio.size() * 2)
	for i in audio.size():
		data.encode_s16(i * 2, int(clampf(audio[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav


## The audio at another rate plus its pitch marks, cached. Used for playback.
## Returns {audio, marks, periods, voiced}: one mark per vocal-cord cycle
## (or every 9 ms where there's no pitch), its period in samples, and 1 if
## the mark is pitched.
func render_data(rate: int) -> Dictionary:
	if _cache.has(rate):
		return _cache[rate]
	var src := audio if rate == sample_rate else BlabberSampleBank.resample(audio, sample_rate, rate)
	var scale := float(rate) / sample_rate
	var marks := PackedFloat32Array()
	var periods := PackedFloat32Array()
	var voiced := PackedByteArray()
	var grain := 0.009 * rate
	var n := src.size()
	# Marks go on the peaks of one polarity, whichever is stronger, so they
	# don't jump between the up and down swings of a cycle.
	var hi := 0.0
	var lo := 0.0
	for v in src:
		hi = maxf(hi, v)
		lo = minf(lo, v)
	var sign := 1.0 if hi >= -lo else -1.0
	var pos := 0.0
	var last_voiced := false
	while pos < n:
		var f := pitch_at(pos / scale)
		if f <= 0.0:
			marks.append(pos)
			periods.append(grain)
			voiced.append(0)
			pos += grain
			last_voiced = false
			continue
		var period := rate / f
		# Snap to the strongest peak near where the next cycle should be.
		# The first mark after a gap searches a whole cycle to find its phase.
		var search := int(period * (0.5 if not last_voiced else 0.2))
		var best := int(pos)
		var best_v := -INF
		for i in range(maxi(0, int(pos) - search), mini(n, int(pos) + search + 1)):
			var v := src[i] * sign
			if v > best_v:
				best_v = v
				best = i
		if not marks.is_empty() and best <= marks[-1] + period * 0.5:
			best = int(marks[-1] + period)
		if best >= n:
			break
		marks.append(best)
		periods.append(period)
		voiced.append(1)
		pos = best + period
		last_voiced = true
	if marks.is_empty():
		marks.append(n * 0.5)
		periods.append(grain)
		voiced.append(0)
	var d := {"audio": src, "marks": marks, "periods": periods, "voiced": voiced}
	_cache[rate] = d
	return d
