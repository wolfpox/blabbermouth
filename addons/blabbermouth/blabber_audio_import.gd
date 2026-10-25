class_name BlabberAudioImport
extends Node
## Gets mono audio out of files and streams, for building sample banks.
##
## WAV files are read instantly. OGG and MP3 (or any AudioStream) are decoded
## by playing them silently through a capture bus. That takes as long as
## the clip on Godot 4.3, and is instant on versions that support
## AudioStreamPlayback.mix_audio().
##
## [codeblock]
## var importer := BlabberAudioImport.new()
## add_child(importer)
## var result := await importer.load_file("res://my_voice.ogg")
## if result.ok:
##     var bank := BlabberSampleBank.from_samples(result.samples, result.rate)
## [/codeblock]

## Progress 0..1 while decoding a compressed file.
signal progress(amount: float)

const DECODE_BUS := &"BlabberDecode"
const MAX_SECONDS := 30.0
const EXTENSIONS := ["wav", "ogg", "mp3"]


## Loads a wav, ogg or mp3 file. Returns {ok, samples, rate, error}.
func load_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		return _fail("File not found: " + path)
	match ext:
		"wav":
			return parse_wav(FileAccess.get_file_as_bytes(path))
		"ogg":
			var ogg := AudioStreamOggVorbis.load_from_file(path)
			if ogg == null:
				return _fail("Could not read this OGG file.")
			return await decode_stream(ogg)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			if mp3.get_length() <= 0.0:
				return _fail("Could not read this MP3 file.")
			return await decode_stream(mp3)
	return _fail("Unsupported file type .%s. Use WAV, OGG or MP3." % ext)


## Web only: opens the browser's file picker and decodes the chosen file
## with the browser (so .m4a voice memos work too). Some browsers refuse to
## open a picker from code; BlabberWeb.place_file_input() is more reliable.
## Returns {ok, samples, rate, error, name}; ok is false with an empty error
## if the user cancelled.
func pick_file_web() -> Dictionary:
	if not BlabberWeb.available():
		return _fail("pick_file_web() only works in a web export.")
	BlabberWeb.pick_file()
	var st := "picking"
	while st == "picking" or st == "decoding":
		await get_tree().process_frame
		st = BlabberWeb.state()
		if st == "decoding":
			progress.emit(0.5)
	if st == "done":
		var samples := BlabberWeb.take_file()
		progress.emit(1.0)
		return {"ok": not samples.is_empty(), "samples": samples, "rate": BlabberWeb.rate(), "error": "",
			"name": str(JavaScriptBridge.eval("window.BlabberWeb.name", true))}
	if st == "error":
		return _fail(BlabberWeb.error())
	return _fail("")


## Decodes any AudioStream to mono samples.
func decode_stream(stream: AudioStream) -> Dictionary:
	if stream is AudioStreamWAV:
		var r := from_wav_stream(stream)
		if r.ok:
			return r
	var length := minf(stream.get_length(), MAX_SECONDS)
	if length <= 0.0:
		length = MAX_SECONDS
	var fast := _decode_fast(stream, length)
	if fast.ok:
		return fast
	return await _decode_realtime(stream, length)


## Reads a WAV file from bytes (8/16/24/32-bit PCM or 32-bit float, any channels).
static func parse_wav(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return _fail("Not a WAV file.")
	var pos := 12
	var fmt := -1
	var channels := 0
	var rate := 0
	var bits := 0
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt ":
			fmt = bytes.decode_u16(body)
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
			if fmt == 0xFFFE and size >= 26:
				fmt = bytes.decode_u16(body + 24)
		elif id == "data":
			data_at = body
			data_len = mini(size, bytes.size() - body)
			break
		pos = body + size + (size & 1)
	if data_at < 0 or channels <= 0 or rate <= 0:
		return _fail("This WAV file is missing its audio data.")
	if not (fmt == 1 or (fmt == 3 and bits == 32)) or not bits in [8, 16, 24, 32]:
		return _fail("Unsupported WAV encoding (format %d, %d-bit)." % [fmt, bits])
	var bps := bits / 8
	var frame := bps * channels
	var n := mini(data_len / frame, int(MAX_SECONDS * rate))
	var out := PackedFloat32Array()
	out.resize(n)
	var inv := 1.0 / channels
	for i in n:
		var s := 0.0
		var o := data_at + i * frame
		for c in channels:
			var p := o + c * bps
			match bits:
				8: s += (bytes[p] - 128) / 128.0
				16: s += bytes.decode_s16(p) / 32768.0
				24:
					var v := bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16)
					if v & 0x800000:
						v -= 0x1000000
					s += v / 8388608.0
				32: s += bytes.decode_float(p) if fmt == 3 else bytes.decode_s32(p) / 2147483648.0
		out[i] = s * inv
	return {"ok": true, "samples": out, "rate": rate, "error": ""}


## Reads an uncompressed AudioStreamWAV, such as a mic recording.
static func from_wav_stream(wav: AudioStreamWAV) -> Dictionary:
	if wav.format != AudioStreamWAV.FORMAT_16_BITS and wav.format != AudioStreamWAV.FORMAT_8_BITS:
		return _fail("Compressed WAV streams are not supported.")
	var data := wav.data
	var ch := 2 if wav.stereo else 1
	var bps := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var n := data.size() / (bps * ch)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		for c in ch:
			var p := (i * ch + c) * bps
			s += data.decode_s16(p) / 32768.0 if bps == 2 else data.decode_s8(p) / 128.0
		out[i] = s / ch
	return {"ok": true, "samples": out, "rate": wav.mix_rate, "error": ""}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "samples": PackedFloat32Array(), "rate": 0, "error": msg}


## Instant decode where the engine supports it (Godot 4.4+).
func _decode_fast(stream: AudioStream, length: float) -> Dictionary:
	var pb := stream.instantiate_playback()
	if pb == null or not pb.has_method("mix_audio") or not pb.has_method("start"):
		return _fail("")
	var rate := 44100
	pb.call("start", 0.0)
	var out := PackedFloat32Array()
	var total := int(length * rate)
	while out.size() < total:
		var chunk: PackedVector2Array = pb.call("mix_audio", 1.0, 4096)
		if chunk.is_empty():
			break
		for f in chunk:
			out.append((f.x + f.y) * 0.5)
		if pb.has_method("is_playing") and not pb.call("is_playing"):
			break
	out.resize(mini(out.size(), total))
	return {"ok": not out.is_empty(), "samples": out, "rate": rate, "error": ""}


## Plays the stream silently on a capture bus and collects what comes out.
func _decode_realtime(stream: AudioStream, length: float) -> Dictionary:
	var bus := _ensure_bus()
	var cap: AudioEffectCapture = AudioServer.get_bus_effect(bus, 0)
	cap.clear_buffer()
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = DECODE_BUS
	add_child(player)
	var rate := int(AudioServer.get_mix_rate())
	var out := PackedFloat32Array()
	var total := int(length * rate)
	player.play()
	var state := {"done": false} # Lambdas capture by value, so use a dictionary.
	player.finished.connect(func() -> void: state.done = true)
	while not state.done and out.size() < total:
		await get_tree().process_frame
		_drain(cap, out)
		progress.emit(clampf(float(out.size()) / total, 0.0, 1.0))
	# Pick up what is still in the buffer.
	await get_tree().process_frame
	_drain(cap, out)
	player.queue_free()
	out.resize(mini(out.size(), total))
	progress.emit(1.0)
	if out.is_empty():
		return _fail("Decoding produced no audio. Is an audio output device available?")
	return {"ok": true, "samples": out, "rate": rate, "error": ""}


static func _drain(cap: AudioEffectCapture, out: PackedFloat32Array) -> void:
	var n := cap.get_frames_available()
	if n <= 0:
		return
	for f in cap.get_buffer(n):
		out.append((f.x + f.y) * 0.5)


static func _ensure_bus() -> int:
	var idx := AudioServer.get_bus_index(DECODE_BUS)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, DECODE_BUS)
	AudioServer.set_bus_send(idx, &"Master")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 1.0
	AudioServer.add_bus_effect(idx, cap)
	# The capture effect runs before the bus volume, so it hears the stream
	# while the speakers do not.
	AudioServer.set_bus_volume_db(idx, -80.0)
	return idx
