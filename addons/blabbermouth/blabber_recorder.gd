class_name BlabberRecorder
extends Node
## Records from the microphone, for making sample voices.
##
## Requires Project Settings > Audio > Driver > Enable Input. On Android,
## also tick the RECORD_AUDIO permission in the export preset. On the web,
## the page must be served over HTTPS; the browser asks for permission and
## records through BlabberWeb.
##
## [codeblock]
## recorder.start()
## # ...
## var result := recorder.stop()
## var bank := BlabberSampleBank.from_samples(result.samples, result.rate)
## [/codeblock]

## Live input level, 0..1, every frame while recording.
signal level_changed(level: float)
## Recording ended (by stop() or the time limit). Same result as stop().
signal stopped(result: Dictionary)

const MIC_BUS := &"BlabberMic"
const MAX_SECONDS := 30.0

var recording := false
## Everything captured so far (mono). Handy for drawing a live waveform.
var samples := PackedFloat32Array()
var rate := 44100

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture


func _ready() -> void:
	set_process(false)


## Why recording can't start, or "" if it can.
static func problem() -> String:
	if BlabberWeb.available():
		return "" # The browser records directly (see BlabberWeb).
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return "Turn on Project Settings > Audio > Driver > Enable Input to use the microphone."
	return ""


func start() -> bool:
	var p := problem()
	if p != "":
		push_warning("BlabberRecorder: " + p)
		return false
	samples = PackedFloat32Array()
	if BlabberWeb.available():
		# The browser asks for permission and starts asynchronously.
		BlabberWeb.start_mic()
		rate = 48000
	else:
		if OS.get_name() == "Android":
			OS.request_permission("android.permission.RECORD_AUDIO")
		_setup()
		_capture.clear_buffer()
		rate = int(AudioServer.get_mix_rate())
		_player.play()
	recording = true
	set_process(true)
	return true


## Stops and returns {ok, samples, rate, error}.
func stop() -> Dictionary:
	if not recording:
		return {"ok": false, "samples": PackedFloat32Array(), "rate": 0, "error": "Not recording."}
	_drain()
	recording = false
	if BlabberWeb.available():
		BlabberWeb.stop_mic()
	else:
		_player.stop()
	set_process(false)
	level_changed.emit(0.0)
	var result := {"ok": true, "samples": samples, "rate": rate, "error": ""}
	if samples.size() < rate * 0.2:
		result.ok = false
		result.error = "Nothing was recorded. Check the microphone and its permission."
	stopped.emit(result)
	return result


func seconds() -> float:
	return samples.size() / float(rate)


func _process(_delta: float) -> void:
	if BlabberWeb.available():
		var st := BlabberWeb.state()
		if st == "error":
			var err := BlabberWeb.error()
			BlabberWeb.stop_mic()
			recording = false
			set_process(false)
			level_changed.emit(0.0)
			stopped.emit({"ok": false, "samples": PackedFloat32Array(), "rate": 0, "error": err})
			return
		if st == "starting":
			return
	var before := samples.size()
	_drain()
	var peak := 0.0
	for i in range(before, samples.size()):
		peak = maxf(peak, absf(samples[i]))
	level_changed.emit(clampf(peak, 0.0, 1.0))
	if seconds() >= MAX_SECONDS:
		stop()


func _drain() -> void:
	if BlabberWeb.available():
		var r := BlabberWeb.rate()
		if r > 0:
			rate = r
		samples.append_array(BlabberWeb.take_mic())
		return
	var n := _capture.get_frames_available()
	if n > 0:
		for f in _capture.get_buffer(n):
			samples.append((f.x + f.y) * 0.5)


func _setup() -> void:
	if _player != null:
		return
	var idx := AudioServer.get_bus_index(MIC_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MIC_BUS)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.0
		AudioServer.add_bus_effect(idx, _capture)
		# Capture runs before the volume, so we record without echoing the mic.
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		_capture = AudioServer.get_bus_effect(idx, 0)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = MIC_BUS
	add_child(_player)
