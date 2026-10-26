extends RefCounted
## A line being edited: plain text, the effects on each character, and pauses.
## Turns into Blabbermouth's tagged text (to_source) and back (from_source),
## so the editor never makes the user type tags.

## Every effect the toolbar offers. Each group allows one effect per character.
const FX := {
	"shout": {"label": "Shout", "group": "volume", "voice": "louder, higher, tenser", "open": "[shout]", "close": "[/shout]"},
	"whisper": {"label": "Whisper", "group": "volume", "voice": "breath only, no voicing", "open": "[whisper]", "close": "[/whisper]"},
	"shiver": {"label": "Shiver", "group": "motion", "voice": "trembling, fast vibrato", "open": "[shiver]", "close": "[/shiver]"},
	"wave": {"label": "Wave", "group": "motion", "voice": "pitch rolls up and down", "open": "[wave]", "close": "[/wave]"},
	"swell": {"label": "Swell", "group": "motion", "voice": "grows louder and higher", "open": "[swell]", "close": "[/swell]"},
	"bounce": {"label": "Bounce", "group": "motion", "voice": "bright, a bit quicker", "open": "[bounce]", "close": "[/bounce]"},
	"droop": {"label": "Droop", "group": "motion", "voice": "sinks lower and slower", "open": "[droop]", "close": "[/droop]"},
	"jolt": {"label": "Jolt", "group": "motion", "voice": "rough, punchy, growly", "open": "[jolt]", "close": "[/jolt]"},
	"slow": {"label": "Slow", "group": "pace", "voice": "0.6× speed", "open": "[speed=0.6]", "close": "[/speed]"},
	"fast": {"label": "Fast", "group": "pace", "voice": "1.5× speed", "open": "[speed=1.5]", "close": "[/speed]"},
	"high": {"label": "High", "group": "pitch", "voice": "1.25× pitch", "open": "[pitch=1.25]", "close": "[/pitch]"},
	"low": {"label": "Low", "group": "pitch", "voice": "0.8× pitch", "open": "[pitch=0.8]", "close": "[/pitch]"},
}
const GROUPS := ["volume", "pace", "pitch", "motion"]
const PAUSE_SECONDS := 0.5
const MAX_TEXT := 5000
## Stands in for a pause in the bubble view, until the badge replaces it.
const MARK := "\uE000"

var text := ""
## One Dictionary per character: group -> effect name.
var styles: Array = []
## Position (0..text.length(), a pause after text[pos - 1]) -> seconds.
var pauses := {}

static var _re: RegEx


## Square brackets would read as tags, so typed ones become parentheses.
static func clean(t: String) -> String:
	return t.replace("[", "(").replace("]", ")").replace(MARK, "").left(MAX_TEXT)


## Changes the text, keeping each untouched character's effects. New
## characters take the effects that both their neighbors share, so typing
## inside a shouted word keeps shouting but typing after it doesn't.
func set_text(t: String) -> void:
	t = clean(t)
	var old := text
	if t == old:
		return
	var n := mini(old.length(), t.length())
	var p := 0
	while p < n and old[p] == t[p]:
		p += 1
	var s := 0
	while s < n - p and old[old.length() - 1 - s] == t[t.length() - 1 - s]:
		s += 1
	var del_end := old.length() - s
	var ins := t.length() - s - p
	var inherit := {}
	if ins > 0 and p > 0 and del_end < old.length():
		var before: Dictionary = styles[p - 1]
		var after: Dictionary = styles[del_end]
		for g in before:
			if after.get(g) == before[g]:
				inherit[g] = before[g]
	var next: Array = styles.slice(0, p)
	for i in ins:
		next.append(inherit.duplicate())
	next.append_array(styles.slice(del_end))
	styles = next
	var moved := {}
	for pos in pauses:
		if pos <= p:
			moved[pos] = pauses[pos]
		elif pos >= del_end:
			moved[pos + ins - (del_end - p)] = pauses[pos]
	pauses = moved
	text = t


## The range to format: the selection, or the whole line when nothing is selected.
func range_or_all(sel: Vector2i) -> Vector2i:
	if sel.x < sel.y:
		return Vector2i(clampi(sel.x, 0, text.length()), clampi(sel.y, 0, text.length()))
	return Vector2i(0, text.length())


## True if every non-space character in [a, b) has the effect.
func is_on(fx: String, a: int, b: int) -> bool:
	var g: String = FX[fx].group
	var any := false
	for i in range(a, b):
		if _is_space(text[i]):
			continue
		if styles[i].get(g) != fx:
			return false
		any = true
	return any


## Adds the effect to [a, b), replacing others from its group, or removes it
## if the whole range already has it.
func toggle(fx: String, a: int, b: int) -> void:
	var g: String = FX[fx].group
	var off := is_on(fx, a, b)
	for i in range(a, b):
		if off:
			styles[i].erase(g)
		else:
			styles[i][g] = fx


## A pause after position pos, or none if there is one.
func toggle_pause(pos: int) -> void:
	if pauses.has(pos):
		pauses.erase(pos)
	elif pos > 0:
		pauses[pos] = PAUSE_SECONDS


func has_pause(pos: int) -> bool:
	return pauses.has(pos)


## Removes every effect in [a, b) and the pauses inside or right after it.
func clear(a: int, b: int) -> void:
	for i in range(a, b):
		styles[i] = {}
	for pos in pauses.keys():
		if pos > a and pos <= b:
			pauses.erase(pos)


## Grows a range to whole words (up to the spaces around them), and trims
## spaces off its ends. Returns an empty range at a if nothing is left.
func snap(a: int, b: int) -> Vector2i:
	a = clampi(a, 0, text.length())
	b = clampi(b, a, text.length())
	while a < b and _is_space(text[a]):
		a += 1
	while b > a and _is_space(text[b - 1]):
		b -= 1
	if a == b:
		return Vector2i(a, a)
	while a > 0 and not _is_space(text[a - 1]):
		a -= 1
	while b < text.length() and not _is_space(text[b]):
		b += 1
	return Vector2i(a, b)


## The tagged text the voice reads.
func to_source() -> String:
	return _source(false)


## Stretches of the line that have effects or end in a pause:
## [{start, end, fx: [names], pause: seconds or 0.0}], in order.
func marks() -> Array:
	var out: Array = []
	var i := 0
	var n := text.length()
	while i < n:
		var st: Dictionary = styles[i]
		var j := i + 1
		while j < n and styles[j] == st and not pauses.has(j):
			j += 1
		var pause: float = pauses.get(j, 0.0)
		if not st.is_empty() or pause > 0.0:
			var fx: Array = []
			for g in GROUPS:
				if st.has(g):
					fx.append(st[g])
			var r := _trim(i, j)
			if st.is_empty():
				r.x = _words_before(r.y, 2, r.x)
			if r.x < r.y:
				out.append({"start": r.x, "end": r.y, "fx": fx, "pause": pause})
			elif pause > 0.0 and not out.is_empty() and out[-1].end <= j:
				out[-1].pause = pause
		i = j
	return out


## BBCode for the bubble while editing: the line's effects, a highlight on
## [sel_a, sel_b), and a small badge where each pause is. Returns {bbcode, map}:
## map[i] is the text position of the bubble's visible character i (badges map
## to the position of their pause), plus one entry for the end.
func edit_view(font_size: int, muted: Color, sel_a: int, sel_b: int, highlight: Color, badge_font_path := "") -> Dictionary:
	var bb := BlabberParser.to_bbcode(_source(true), font_size, muted)
	var order: Array = pauses.keys()
	order.sort()
	var out := ""
	var map := PackedInt32Array()
	var at := 0
	var mark_i := 0
	var lit := false
	var hl_open := "[bgcolor=#%s]" % highlight.to_html()
	var i := 0
	while i < bb.length():
		var c := bb[i]
		if c == "[":
			var e := bb.find("]", i)
			if e < 0:
				e = bb.length() - 1
			if lit:
				out += "[/bgcolor]"
				lit = false
			out += bb.substr(i, e - i + 1)
			i = e + 1
			continue
		if c == MARK:
			if lit:
				out += "[/bgcolor]"
				lit = false
			var pos: int = order[mark_i] if mark_i < order.size() else at
			mark_i += 1
			var label := " %ss " % _secs(pauses.get(pos, PAUSE_SECONDS))
			var badge := label
			var tint := muted if muted.a > 0.0 else Color(0.5, 0.5, 0.5)
			badge = "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [Color(tint, 0.16).to_html(), tint.to_html(), badge]
			badge = "[font_size=%d]%s[/font_size]" % [maxi(roundi(font_size * 0.55), 10), badge]
			if badge_font_path != "":
				badge = "[font=%s]%s[/font]" % [badge_font_path, badge]
			out += " " + badge
			for k in label.length() + 1:
				map.append(pos)
			i += 1
			continue
		var want := at >= sel_a and at < sel_b
		if want and not lit:
			out += hl_open
			lit = true
		elif not want and lit:
			out += "[/bgcolor]"
			lit = false
		out += c
		map.append(at)
		at += 1
		i += 1
	if lit:
		out += "[/bgcolor]"
	map.append(at)
	return {"bbcode": out, "map": map}


## Reads tagged text. Tags the toolbar doesn't offer are approximated
## (emotions become their matching effect, any slower speed becomes Slow)
## or dropped (volume, BBCode).
static func from_source(src: String) -> RefCounted:
	var m: RefCounted = (load("res://demo/line_model.gd") as GDScript).new()
	if _re == null:
		_re = RegEx.new()
		_re.compile("\\[(/?)([A-Za-z_]+)(?:=([^\\]]*))?\\]")
	var cur := {}
	var from_emote := {}
	var t := ""
	var st: Array = []
	var i := 0
	while i < src.length() and t.length() < MAX_TEXT:
		if src[i] == "[":
			var mm := _re.search(src, i)
			if mm and mm.get_start() == i:
				_read_tag(mm.get_string(2).to_lower(), mm.get_string(1) == "/", mm.get_string(3).strip_edges().to_lower(), cur, from_emote, m.pauses, t.length())
				i = mm.get_end()
				continue
		t += src[i]
		st.append(cur.duplicate())
		i += 1
	m.text = clean(t)
	m.styles = st
	for pos in m.pauses.keys():
		if pos <= 0 or pos > t.length():
			m.pauses.erase(pos)
	return m


static func _read_tag(tag: String, closing: bool, val: String, cur: Dictionary, from_emote: Dictionary, pauses: Dictionary, at: int) -> void:
	match tag:
		"shout", "whisper":
			if closing:
				cur.erase("volume")
			else:
				cur.volume = tag
		"shiver", "wave", "swell", "bounce", "droop", "jolt":
			if closing:
				if cur.get("motion") == tag:
					cur.erase("motion")
			else:
				cur.motion = tag
		"emote":
			if closing:
				for g in from_emote:
					cur.erase(g)
				from_emote.clear()
			elif val in ["whisper", "shout"]:
				cur.volume = val
				from_emote.volume = true
			elif BlabberParser.EMOTE_EFFECT.has(val):
				cur.motion = BlabberParser.EMOTE_EFFECT[val]
				from_emote.motion = true
		"speed", "pitch":
			var g := "pace" if tag == "speed" else "pitch"
			var f := val.to_float() if val.is_valid_float() else 1.0
			if closing or is_equal_approx(f, 1.0):
				cur.erase(g)
			elif tag == "speed":
				cur[g] = "slow" if f < 1.0 else "fast"
			else:
				cur[g] = "low" if f < 1.0 else "high"
		"pause":
			var secs := val.to_float() if val.is_valid_float() else 0.4
			pauses[at] = clampf(secs, 0.05, 5.0)
		"reset":
			cur.clear()
			from_emote.clear()


func _source(with_marks: bool) -> String:
	var out := ""
	var open: Array = []
	var n := text.length()
	for i in n + 1:
		var want: Dictionary = styles[i] if i < n else {}
		for k in range(open.size() - 1, -1, -1):
			var name: String = open[k]
			if want.get(FX[name].group) != name:
				out += FX[name].close
				open.remove_at(k)
		if pauses.has(i):
			out += (MARK if with_marks else "") + "[pause=%s]" % _secs(pauses[i])
		if i == n:
			break
		for g in GROUPS:
			if want.has(g) and not want[g] in open:
				out += FX[want[g]].open
				open.append(want[g])
		out += text[i]
	return out


## Where the last n words before position b start (not before lo).
func _words_before(b: int, n: int, lo: int) -> int:
	var a := b
	for k in n:
		while a > lo and _is_space(text[a - 1]):
			a -= 1
		while a > lo and not _is_space(text[a - 1]):
			a -= 1
	return a


func _trim(a: int, b: int) -> Vector2i:
	while a < b and _is_space(text[a]):
		a += 1
	while b > a and _is_space(text[b - 1]):
		b -= 1
	return Vector2i(a, b)


static func _secs(v: float) -> String:
	var s := str(snappedf(v, 0.01))
	return s.trim_suffix(".0")


static func _is_space(c: String) -> bool:
	return c == " " or c == "\n" or c == "\t"
