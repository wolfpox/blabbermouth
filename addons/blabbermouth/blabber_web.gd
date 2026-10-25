class_name BlabberWeb
extends RefCounted
## Browser helpers for web exports: microphone recording and file picking
## through the browser's own audio APIs.
##
## The browser decodes almost any audio file (including phone voice memos
## in .m4a), and recording works without threads or special server headers,
## so it runs on plain static hosting such as GitHub Pages.
## Every function is safe to call on other platforms; it just does nothing.

const JS := """
window.BlabberWeb = window.BlabberWeb || (function () {
	const W = { state: 'idle', error: '', rate: 0, name: '', level: 0, recording: false, data: null, chunks: [] };
	const MAX_SECONDS = 30;
	W.ctx = function () {
		if (!W._ctx) W._ctx = new (window.AudioContext || window.webkitAudioContext)();
		return W._ctx;
	};
	function mixdown(buf) {
		const n = buf.length, ch = buf.numberOfChannels, out = new Float32Array(n);
		for (let c = 0; c < ch; c++) {
			const d = buf.getChannelData(c);
			for (let i = 0; i < n; i++) out[i] += d[i] / ch;
		}
		return out;
	}
	const ACCEPT = 'audio/*,.wav,.mp3,.ogg,.oga,.m4a,.aac,.flac,.webm,.opus,.caf';
	W.decodeFile = async function (f) {
		W.state = 'decoding'; W.name = f.name; W.error = '';
		try {
			const ab = await f.arrayBuffer();
			const ctx = W.ctx();
			// Callback form for older Safari; also catch the promise form's rejection.
			const buf = await new Promise(function (ok, fail) {
				const r = ctx.decodeAudioData(ab, ok, fail);
				if (r && r.catch) r.catch(fail);
			});
			let m = mixdown(buf);
			const max = Math.floor(MAX_SECONDS * buf.sampleRate);
			if (m.length > max) m = m.slice(0, max);
			W.rate = buf.sampleRate; W.data = m; W.state = 'done';
		} catch (e) {
			W.state = 'error'; W.error = 'This browser could not read ' + f.name + '. Try another file.';
		}
	};
	// Opens the picker from code. Browsers may refuse this outside a real
	// click on the page, so prefer placeFileInput().
	W.pickFile = function () {
		W.state = 'picking'; W.error = '';
		const input = document.createElement('input');
		input.type = 'file'; input.accept = ACCEPT; input.style.display = 'none';
		document.body.appendChild(input);
		input.addEventListener('cancel', function () { input.remove(); if (W.state === 'picking') W.state = 'idle'; });
		input.onchange = function () {
			const f = input.files && input.files[0];
			input.remove();
			if (f) W.decodeFile(f); else W.state = 'idle';
		};
		input.click();
	};
	// An invisible file input laid over a button drawn by Godot, so the
	// user's tap lands on a real input (the most reliable way, also on iOS).
	W.placeFileInput = function (x, y, w, h, visible) {
		// A transparent <label> over the button: tapping a label anywhere opens
		// its file input, on every browser.
		let input = W._overlay;
		if (!input) {
			input = document.createElement('label');
			input.style.cssText = 'position:fixed;z-index:10;cursor:pointer;background:transparent;-webkit-tap-highlight-color:transparent;';
			const file = document.createElement('input');
			file.type = 'file'; file.accept = ACCEPT;
			file.style.cssText = 'position:absolute;width:1px;height:1px;opacity:0;overflow:hidden;pointer-events:none;';
			file.onchange = function () {
				const f = file.files && file.files[0];
				if (f) W.decodeFile(f);
				file.value = '';
			};
			input.appendChild(file);
			document.body.appendChild(input);
			W._overlay = input;
		}
		const canvas = document.querySelector('canvas');
		const r = canvas ? canvas.getBoundingClientRect() : { left: 0, top: 0 };
		input.style.left = (r.left + x) + 'px'; input.style.top = (r.top + y) + 'px';
		input.style.width = w + 'px'; input.style.height = h + 'px';
		input.style.display = visible ? 'block' : 'none';
	};
	W.reset = function () { if (W.state === 'done' || W.state === 'error') { W.state = 'idle'; W.data = null; } };
	W.takeData = function () {
		const d = W.data; W.data = null; W.state = 'idle';
		return d ? new Uint8Array(d.buffer) : null;
	};
	W.startMic = async function () {
		W.chunks = []; W.level = 0; W.error = ''; W.state = 'starting';
		if (!window.isSecureContext || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			W.state = 'error'; W.error = 'The microphone needs a secure (https) page.'; return;
		}
		try {
			const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: true, autoGainControl: true } });
			const ctx = W.ctx();
			if (ctx.state !== 'running') await ctx.resume();
			const src = ctx.createMediaStreamSource(stream);
			const proc = ctx.createScriptProcessor(4096, 1, 1);
			proc.onaudioprocess = function (e) {
				if (!W.recording) return;
				const d = new Float32Array(e.inputBuffer.getChannelData(0));
				W.chunks.push(d);
				let p = 0;
				for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > p) p = a; }
				W.level = p;
			};
			const mute = ctx.createGain();
			mute.gain.value = 0;
			src.connect(proc); proc.connect(mute); mute.connect(ctx.destination);
			W._mic = { stream: stream, src: src, proc: proc, mute: mute };
			W.rate = ctx.sampleRate; W.recording = true; W.state = 'recording';
		} catch (e) {
			W.state = 'error';
			W.error = (e && e.name === 'NotAllowedError') ? 'Microphone permission was denied. Allow it in the browser and try again.' : 'Could not open the microphone (' + (e && e.name ? e.name : e) + ').';
		}
	};
	W.takeNew = function () {
		if (!W.chunks.length) return null;
		let n = 0;
		for (const c of W.chunks) n += c.length;
		const out = new Float32Array(n);
		let o = 0;
		for (const c of W.chunks) { out.set(c, o); o += c.length; }
		W.chunks = [];
		return new Uint8Array(out.buffer);
	};
	W.stopMic = function () {
		W.recording = false;
		if (W._mic) {
			W._mic.proc.disconnect(); W._mic.src.disconnect(); W._mic.mute.disconnect();
			W._mic.stream.getTracks().forEach(function (t) { t.stop(); });
			W._mic = null;
		}
		W.level = 0;
		if (W.state !== 'error') W.state = 'idle';
	};
	return W;
})();
true;
"""

static var _loaded := false
static var _last_overlay := []
static var _ratio := 0.0


static func available() -> bool:
	return OS.has_feature("web")


static func _js(code: String) -> Variant:
	if not available():
		return null
	if not _loaded:
		JavaScriptBridge.eval(JS, true)
		_loaded = true
	return JavaScriptBridge.eval(code, true)


## "idle", "picking", "decoding", "done", "starting", "recording" or "error".
static func state() -> String:
	var s = _js("window.BlabberWeb.state")
	return str(s) if s != null else "idle"


static func error() -> String:
	return str(_js("window.BlabberWeb.error"))


static func rate() -> int:
	var r = _js("window.BlabberWeb.rate")
	return int(r) if r != null else 0


static func level() -> float:
	var l = _js("window.BlabberWeb.level")
	return float(l) if l != null else 0.0


## Opens the browser's file picker. Call from a button press.
static func pick_file() -> void:
	_js("window.BlabberWeb.pickFile()")


## Lays an invisible file input over a Control (such as a "Load file" button),
## so tapping it opens the browser's file picker. Call every frame or when the
## layout changes; pass visible = false to hide it, and clip to keep it inside
## a scrolling area. Then watch state() for
## "decoding", "done" (use take_file()) or "error".
static func place_file_input(control: Control, visible := true, clip := Rect2()) -> void:
	if not available():
		return
	var r := control.get_global_rect()
	if clip.has_area():
		r = r.intersection(clip)
		visible = visible and r.has_area()
	var win := control.get_window()
	var to_css := 1.0
	if win.content_scale_size.x > 0:
		to_css = float(win.size.x) / win.content_scale_size.x
	to_css /= pixel_ratio()
	var key := [r.position.x, r.position.y, r.size.x, r.size.y, visible, to_css]
	if key == _last_overlay:
		return
	_last_overlay = key
	_js("window.BlabberWeb.placeFileInput(%f, %f, %f, %f, %s)" % [r.position.x * to_css, r.position.y * to_css,
		r.size.x * to_css, r.size.y * to_css, "true" if visible else "false"])


## Clears a finished "done" or "error" state.
static func reset() -> void:
	_js("window.BlabberWeb.reset()")


## The file's name, once state() is "done".
static func file_name() -> String:
	return str(_js("window.BlabberWeb.name"))


## The decoded file, once state() is "done".
static func take_file() -> PackedFloat32Array:
	return _floats(_js("window.BlabberWeb.takeData()"))


static func start_mic() -> void:
	_js("window.BlabberWeb.startMic()")


## Samples recorded since the last call.
static func take_mic() -> PackedFloat32Array:
	return _floats(_js("window.BlabberWeb.takeNew()"))


static func stop_mic() -> void:
	_js("window.BlabberWeb.stopMic()")


## Screen pixels per CSS pixel (2-3 on phones).
static func pixel_ratio() -> float:
	if _ratio <= 0.0:
		var r = _js("window.devicePixelRatio || 1")
		_ratio = float(r) if r != null else 1.0
	return _ratio


## Saves bytes to the user's downloads.
static func download(bytes: PackedByteArray, file_name: String, mime := "application/octet-stream") -> void:
	if available():
		JavaScriptBridge.download_buffer(bytes, file_name, mime)


static func _floats(v: Variant) -> PackedFloat32Array:
	if v is PackedByteArray:
		return (v as PackedByteArray).to_float32_array()
	return PackedFloat32Array()
