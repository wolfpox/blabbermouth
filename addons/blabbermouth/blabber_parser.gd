class_name BlabberParser
extends RefCounted
## Turns a line of dialogue into a timeline of synth segments.
##
## Steps: read inline tags -> split into sentences and words -> turn each
## word into sounds (phonetic or gibberish) -> add melody, stress and timing.

const P := preload("res://addons/blabbermouth/blabber_phonemes.gd")
const Kind := P.Kind

const KNOWN_TAGS := ["pause", "speed", "pitch", "volume", "emote", "whisper", "shout", "reset"]
const PUNCT_PAUSE := {",": 0.16, ";": 0.22, ":": 0.22, ".": 0.34, "!": 0.32, "?": 0.34, "…": 0.55, "\n": 0.3, "—": 0.2}
const SENTENCE_ENDS := ".!?…\n"
const DIGIT_WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
const NON_WORD_CHARS := "…—–“”‘«»¿¡、。，！？・「」『』"

const VOWEL_DIGRAPHS := {
	"ee": ["i"], "ea": ["i"], "ie": ["i"], "oo": ["u"], "ue": ["u"], "ew": ["u"],
	"ou": ["a", "u"], "ow": ["o", "u"], "ai": ["e", "i"], "ay": ["e", "i"], "ei": ["e", "i"],
	"ey": ["e", "i"], "oa": ["o"], "oi": ["o", "i"], "oy": ["o", "i"], "au": ["o"], "aw": ["o"],
	"oe": ["o", "u"],
}

## Common words that don't follow the spelling rules, as sound names.
const EXCEPTIONS := {
	"a": "uh", "i": "a i", "the": "dh uh", "of": "uh v", "to": "t u", "do": "d u", "who": "h u",
	"you": "y u", "your": "y o r", "one": "w uh n", "once": "w uh n s", "was": "w uh z",
	"what": "w uh t", "come": "k uh m", "some": "s uh m", "love": "l uh v", "done": "d uh n",
	"none": "n uh n", "gone": "g o n", "have": "h ae v", "give": "g ih v", "live": "l ih v",
	"move": "m u v", "lose": "l u z", "whose": "h u z", "sure": "sh u r", "are": "a r",
	"were": "w er", "said": "s e d", "says": "s e z", "does": "d uh z", "there": "dh e r",
	"their": "dh e r", "where": "w e r", "been": "b ih n", "any": "e n i", "many": "m e n i",
	"again": "uh g e n", "water": "w o t er", "is": "ih z", "his": "h ih z", "has": "h ae z",
	"as": "ae z", "us": "uh s", "yes": "y e s", "this": "dh ih s", "thus": "dh uh s",
	"bus": "b uh s", "plus": "p l uh s", "gas": "g ae s", "eye": "a i", "buy": "b a i",
	"bye": "b a i", "hi": "h a i", "key": "k i", "busy": "b ih z i", "business": "b ih z n e s",
	"people": "p i p uh l", "friend": "f r e n d", "could": "k u d", "would": "w u d",
	"should": "sh u d", "put": "p u t", "two": "t u", "through": "th r u", "though": "dh o u",
	"enough": "i n uh f", "thought": "th o t", "bought": "b o t", "brought": "b r o t",
	"laugh": "l ae f", "own": "o u n", "only": "o u n l i", "oh": "o u", "okay": "o u k e i",
	"ok": "o u k e i", "now": "n a u", "how": "h a u", "cow": "k a u", "wow": "w a u",
	"allow": "uh l a u", "great": "g r e i t", "break": "b r e i k", "head": "h e d",
	"dead": "d e d", "bread": "b r e d", "ready": "r e d i", "heavy": "h e v i",
	"bear": "b e r", "wear": "w e r", "swear": "s w e r", "pear": "p e r", "heart": "h a r t",
	"word": "w er d", "world": "w er l d", "work": "w er k", "door": "d o r", "floor": "f l o r",
	"four": "f o r", "our": "a u r", "hour": "a u r", "young": "y uh ng", "touch": "t uh t sh",
	"country": "k uh n t r i", "other": "uh dh er", "mother": "m uh dh er",
	"brother": "b r uh dh er", "nothing": "n uh th ih ng", "money": "m uh n i",
	"honey": "h uh n i", "every": "e v r i", "everyone": "e v r i w uh n",
	"everything": "e v r i th ih ng", "anything": "e n i th ih ng", "someone": "s uh m w uh n",
	"something": "s uh m th ih ng", "become": "b i k uh m", "because": "b i k o z",
	"whole": "h o u l", "minute": "m ih n ih t", "i'm": "a i m", "i've": "a i v",
	"i'll": "a i l", "i'd": "a i d", "don't": "d o u n t", "won't": "w o u n t",
	"can't": "k ae n t", "they're": "dh e r", "you're": "y o r", "we're": "w i r",
}

## Words that start with the soft "th" of "the" (the rest use the "th" of "thin").
const DH_WORDS := {
	"that": true, "these": true, "those": true, "them": true, "they": true, "then": true,
	"than": true, "theirs": true, "themselves": true, "therefore": true, "thee": true, "thy": true,
}

## Words where "ow" before n / l / d / er still sounds like "show".
const OW_LONG := {
	"known": true, "shown": true, "grown": true, "blown": true, "thrown": true, "flown": true,
	"bowl": true, "owner": true, "sown": true, "mown": true,
}

const VOICELESS := ["p", "t", "k", "f", "th", "s", "sh"]
const VOICED_CONS := ["b", "d", "g", "v", "dh", "z", "zh", "m", "n", "ng", "l", "r"]

const LETTER_PHONES := {
	"a": ["a"], "e": ["e"], "i": ["i"], "o": ["o"], "u": ["u"], "y": ["i"],
	"b": ["b"], "c": ["k"], "d": ["d"], "f": ["f"], "g": ["g"], "h": ["h"], "j": ["d", "zh"],
	"k": ["k"], "l": ["l"], "m": ["m"], "n": ["n"], "p": ["p"], "q": ["k"], "r": ["r"],
	"s": ["s"], "t": ["t"], "v": ["v"], "w": ["w"], "x": ["k", "s"], "z": ["z"],
}

static var _re: RegEx


static func _tag_regex() -> RegEx:
	if _re == null:
		_re = RegEx.new()
		_re.compile("\\[(/?)([A-Za-z_]+)(?:=([^\\]]*))?\\]")
	return _re


## Removes Blabbermouth tags but keeps other tags (like BBCode) and all text.
static func strip_tags(text: String) -> String:
	var out := ""
	var last := 0
	for m in _tag_regex().search_all(text):
		if m.get_string(2).to_lower() in KNOWN_TAGS:
			out += text.substr(last, m.get_start() - last)
			last = m.get_end()
	return out + text.substr(last)


## Removes every [tag], including BBCode. For plain Labels.
static func strip_all_tags(text: String) -> String:
	return _tag_regex().sub(text, "", true)


## Returns {segments, display_text, plain_text, visible}. "visible" is the number of
## visible characters, matching Label/RichTextLabel.visible_characters.
static func build(text: String, voice: BlabberVoice) -> Dictionary:
	var scan := _scan(text)
	var sentences := _group(scan.items)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) ^ (voice.language_seed * 7919)
	var segs: Array = []
	_push(segs, _silence(0.01, 0, segs))
	for s in sentences:
		_build_sentence(s, voice, rng, segs)
	_push(segs, _silence(0.15, scan.visible, segs))
	return {"segments": segs, "display_text": strip_tags(text), "plain_text": strip_all_tags(text), "visible": scan.visible}


# --- Step 1: tags and visible characters -------------------------------------

static func _default_state() -> Dictionary:
	return {"speed": 1.0, "pitch": 1.0, "volume": 1.0, "emote": "neutral"}


static func _scan(text: String) -> Dictionary:
	var items: Array = []
	var state := _default_state()
	var vis := 0
	var i := 0
	var n := text.length()
	var re := _tag_regex()
	while i < n:
		var ch := text[i]
		if ch == "[":
			var m := re.search(text, i)
			if m and m.get_start() == i:
				var tag := m.get_string(2).to_lower()
				if tag in KNOWN_TAGS:
					var closing := m.get_string(1) == "/"
					var val := m.get_string(3)
					if tag == "pause":
						items.append({"t": "pause", "s": val.to_float() if val != "" else 0.4, "i": vis})
					else:
						state = _apply_tag(state, tag, val, closing)
				# Unknown tags (BBCode etc.) are silent and invisible.
				i = m.get_end()
				continue
		items.append({"t": "char", "c": ch, "i": vis, "st": state})
		vis += 1
		i += 1
	return {"items": items, "visible": vis}


static func _apply_tag(state: Dictionary, tag: String, val: String, closing: bool) -> Dictionary:
	if tag == "reset":
		return _default_state()
	var s := state.duplicate()
	match tag:
		"speed", "pitch", "volume":
			s[tag] = 1.0 if closing or val == "" else maxf(val.to_float(), 0.05)
		"emote":
			s.emote = "neutral" if closing else val.to_lower()
		"whisper", "shout":
			s.emote = "neutral" if closing else tag
	return s


static func _is_word_char(c: String) -> bool:
	var code := c.unicode_at(0)
	if (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57):
		return true
	if c == "'" or c == "’":
		return true
	return code > 127 and not (c in NON_WORD_CHARS) and c.strip_edges() != ""


# --- Step 2: sentences and words ----------------------------------------------

static func _group(items: Array) -> Array:
	var sentences: Array = []
	var cur := {"tokens": [], "end": ""}
	var word = null
	var last_punct = null
	for it in items:
		var is_word_char: bool = it.t == "char" and _is_word_char(it.c)
		if word != null and not is_word_char:
			cur.tokens.append(word)
			word = null
		if it.t == "pause":
			cur.tokens.append({"t": "pause", "s": it.s, "i": it.i})
			continue
		if is_word_char:
			if word == null:
				word = {"t": "word", "text": "", "idx": [], "st": it.st}
			word.text += it.c
			word.idx.append(it.i)
			continue
		var c: String = it.c
		if not PUNCT_PAUSE.has(c):
			continue # spaces and symbols are silent
		# "..." becomes one long pause.
		if c == "." and last_punct != null and last_punct.c in [".", "…"] and last_punct.i == it.i - 1:
			last_punct.c = "…"
			last_punct.i = it.i
			continue
		# "?!" and similar: extend the last sentence instead of adding a new pause.
		if c != "\n" and cur.tokens.is_empty() and last_punct != null and last_punct.i == it.i - 1:
			last_punct.i = it.i
			continue
		var p := {"t": "punct", "c": c, "i": it.i}
		cur.tokens.append(p)
		last_punct = p
		if c in SENTENCE_ENDS:
			cur.end = c
			sentences.append(cur)
			cur = {"tokens": [], "end": ""}
	if word != null:
		cur.tokens.append(word)
	if not cur.tokens.is_empty():
		sentences.append(cur)
	return sentences


# --- Step 3: words to sounds --------------------------------------------------

static func _is_vowel_letter(c: String) -> bool:
	return c != "" and c in "aeiouy"


static func _is_ascii_word(w: String) -> bool:
	for i in w.length():
		if w.unicode_at(i) > 127 and w[i] != "’":
			return false
	return true


static func _has_vowel(w: String, from: int, to: int) -> bool:
	for k in range(maxi(from, 0), mini(to, w.length())):
		if w[k] in "aeiou" or (w[k] == "y" and k > 0):
			return true
	return false


## Rough letters-to-sounds rules for English-like text. Returns [[phone, end_pos], ...].
static func g2p(w: String) -> Array:
	var out: Array = []
	var n := w.length()
	var key := w.replace("’", "'")
	if EXCEPTIONS.has(key):
		var phs: PackedStringArray = EXCEPTIONS[key].split(" ", false)
		for k in phs.size():
			out.append([phs[k], maxi(1, ceili(float(k + 1) * n / phs.size()))])
		return out
	# "-ed" and "-es" endings, as in "walked", "wanted", "makes", "boxes".
	var ending := ""
	# A "y" after a vowel counts as a consonant here: "played", "stayed".
	if n > 3 and (w.ends_with("ed") or w.ends_with("es")) and _has_vowel(w, 0, n - 3) \
			and (not _is_vowel_letter(w[n - 3]) or (w[n - 3] == "y" and _is_vowel_letter(w[n - 4]))):
		ending = w.right(2)
	var i := 0
	while i < n:
		var c := w[i]
		if c == "'" or c == "’":
			i += 1
			continue
		var nx := w[i + 1] if i + 1 < n else ""
		var nx2 := w[i + 2] if i + 2 < n else ""
		var two := c + nx
		if i == n - 2 and ending != "":
			var before := w[n - 3]
			var prev_ph: String = out[-1][0] if not out.is_empty() else ""
			if ending == "ed":
				if before in "td":
					out.append(["ih", n]); out.append(["d", n])
				else:
					out.append([("t" if prev_ph in VOICELESS else "d"), n])
			else:
				if before in "sxzcg" or w.substr(n - 4, 2) in ["sh", "ch"]:
					out.append(["ih", n]); out.append(["z", n])
				else:
					out.append([("s" if prev_ph in VOICELESS else "z"), n])
			break
		var is_vowel := c in "aeiou" or (c == "y" and i > 0)
		if is_vowel:
			# Silent final e ("make", "time"), but not in "the" or "be".
			if c == "e" and i == n - 1 and i > 0 and not _is_vowel_letter(w[i - 1]) and _has_vowel(w, 0, i - 1):
				i += 1
				continue
			if w.substr(i, 3) == "igh":
				out.append(["a", i + 3]); out.append(["i", i + 3])
				i += 3
				continue
			# "famous", "nervous".
			if c == "o" and i > 1 and i + 3 == n and w.substr(i, 3) == "ous":
				out.append(["uh", i + 2]); out.append(["s", i + 3])
				i += 3
				continue
			# "earth", "learn" (but "ear", "years").
			if w.substr(i, 3) == "ear" and i + 3 < n and not _is_vowel_letter(w[i + 3]) \
					and not (w[i + 3] == "s" and i + 4 == n):
				out.append(["er", i + 3])
				i += 3
				continue
			# "down", "owl", "flower", but "show", "known".
			if two == "ow":
				var wide: bool = (nx2 != "" and nx2 in "nld") or w.substr(i + 2, 2) == "er"
				if wide and not OW_LONG.has(w):
					out.append(["a", i + 2]); out.append(["u", i + 2])
					i += 2
					continue
			if VOWEL_DIGRAPHS.has(two):
				for ph in VOWEL_DIGRAPHS[two]:
					out.append([ph, i + 2])
				i += 2
				continue
			if nx == "r" and c in "eiu" and not _is_vowel_letter(nx2):
				out.append(["er", i + 2])
				i += 2
				continue
			var closed := nx != "" and not _is_vowel_letter(nx) and not _is_vowel_letter(nx2)
			# A single consonant then a silent e makes the vowel long: "make", "hoped".
			var magic := nx != "" and nx != "x" and not _is_vowel_letter(nx) and nx2 == "e" \
					and (i + 3 == n or (i + 4 == n and w[n - 1] in "sd"))
			# "table", "title": a single consonant before a final "le" works the same.
			if nx != "" and nx in "bpgtdfkz" and w.substr(i + 2, 2) == "le" \
					and (i + 4 == n or (i + 5 == n and w[n - 1] in "sd")):
				magic = true
			# "active", "massive" stay short.
			var short_ive := c == "i" and nx == "v" and nx2 == "e" and i > 0 and w[i - 1] in "ts"
			if short_ive:
				magic = false
			var after_w := i > 0 and (w[i - 1] == "w" or (i > 1 and w.substr(i - 2, 2) == "qu"))
			var phs: Array
			var before_ion := w.substr(i + 1, 4) == "tion" or w.substr(i + 1, 4) == "sion"
			if short_ive:
				phs = ["ih"]
			elif magic or before_ion:
				match c:
					"a": phs = ["e", "i"]
					"e": phs = ["i"]
					"i", "y": phs = ["ih"] if not magic else ["a", "i"]
					"o": phs = ["o", "u"]
					"u": phs = ["u"] if i > 0 and w[i - 1] in "rlj" else ["y", "u"]
			elif c == "a" and nx == "l" and (nx2 == "k" or nx2 == "t" or nx2 == "w" \
					or (nx2 == "l" and (i + 3 >= n or not _is_vowel_letter(w[i + 3])))):
				phs = ["o"] # "all", "talk", "salt", "always"
				if nx2 == "k":
					i += 1 # the l in "talk" is silent
			elif c == "a" and after_w and nx != "" and nx in "tnsdlcr":
				phs = ["o"] # "want", "wash", "war", "squad"
				if nx == "r":
					phs = ["o", "r"]
					i += 1
			elif c == "i" and (w.substr(i + 1, 2) == "nd" or w.substr(i + 1, 2) == "ld") \
					and (i + 3 == n or w[i + 3] == "s"):
				phs = ["a", "i"] # "find", "child"
			elif c == "o" and w.substr(i + 1, 2) == "ld":
				phs = ["o", "u"] # "old", "told"
			elif c == "a" and w.substr(i + 1, 3) == "nge":
				phs = ["e", "i"] # "change", "strange"
			elif c == "a" and nx == "r" and not _is_vowel_letter(nx2):
				phs = ["a"] # "car", "large"
			elif c == "u" and not closed and (i == 0 or w[i - 1] in "mhfpbckv"):
				phs = ["y", "u"] # "music", "human"
			elif c == "y" and i == n - 1 and not _has_vowel(w, 0, i):
				phs = ["a", "i"] # "my", "why", "fly"
			elif i == n - 1 and n > 1 and c == "o":
				phs = ["o", "u"] # "go", "hello"
			elif i == n - 1 and n > 1 and c == "a":
				phs = ["uh"] # "pizza", "idea"
			else:
				match c:
					"a": phs = ["ae"] if closed else ["a"]
					"e": phs = ["e"] if closed or i < n - 1 else ["i"]
					"i": phs = ["ih"] if closed else ["i"]
					"o": phs = ["o"]
					"u": phs = ["uh"] if closed else ["u"]
					"y": phs = ["ih"] if closed else ["i"]
			for ph in phs:
				out.append([ph, i + 1])
			i += 1
			continue
		# Consonants. Doubled letters are said once.
		if c == nx:
			i += 1
			continue
		# "nation", "special", "vision", "delicious".
		if i > 0 and c in "tcs" and nx == "i" and nx2 != "" and nx2 in "ao":
			var voiced := c == "s" and _is_vowel_letter(w[i - 1])
			out.append([("zh" if voiced else "sh"), i + 1]); out.append(["uh", i + 3])
			i += 3
			if i < n and w[i] == "u":
				i += 1
			continue
		# "picture", "nature".
		if w.substr(i, 4) == "ture" and (i + 4 == n or (i + 5 == n and w[n - 1] in "sd")):
			out.append(["t", i + 1]); out.append(["sh", i + 2]); out.append(["er", i + 4])
			i += 4
			continue
		# "little", "tables": a soft "ul" sound.
		if c == "l" and nx == "e" and i > 0 and not _is_vowel_letter(w[i - 1]) \
				and (i + 2 == n or (i + 3 == n and w[n - 1] in "sd")):
			out.append(["uh", i + 1]); out.append(["l", i + 2])
			i += 2
			continue
		# "page", "huge", "bridges".
		if (c == "g" or two == "dg") and w[mini(i + (2 if two == "dg" else 1), n - 1)] == "e":
			var e_at := i + (2 if two == "dg" else 1)
			if e_at == n - 1 or (e_at == n - 2 and w[n - 1] in "sd"):
				out.append(["d", e_at]); out.append(["zh", e_at])
				i = e_at
				continue
		var handled := true
		match two:
			"sh": out.append(["sh", i + 2])
			"ch": out.append(["t", i + 2]); out.append(["sh", i + 2])
			"th":
				var soft := (i == 0 and DH_WORDS.has(w)) or (i > 0 and w.substr(i + 2, 2) == "er")
				out.append([("dh" if soft else "th"), i + 2])
			"ph": out.append(["f", i + 2])
			"ck": out.append(["k", i + 2])
			"qu": out.append(["k", i + 2]); out.append(["w", i + 2])
			"wh": out.append(["w", i + 2])
			"tc":
				if nx2 == "h": # "watch": the t is part of the ch
					i += 1
					continue
				handled = false
			"mb":
				if i + 2 == n: # "climb", "lamb"
					out.append(["m", i + 2])
				else:
					handled = false
			"gh":
				if i == 0:
					out.append(["g", i + 2])
			"kn", "wr":
				if i == 0:
					out.append([("n" if c == "k" else "r"), i + 2])
				else:
					handled = false
			"ng":
				if _is_vowel_letter(nx2):
					handled = false
				else:
					out.append(["ng", i + 2])
			_:
				handled = false
		if handled:
			i += 2
			continue
		match c:
			"c":
				out.append([("s" if nx != "" and nx in "eiy" else "k"), i + 1])
			"y":
				out.append(["y", i + 1])
			"h":
				# "ah", "oh": a trailing h is silent.
				if i == 0 or _is_vowel_letter(nx):
					out.append(["h", i + 1])
			"s":
				# Plural and verb "s" after a voiced sound is a "z": "dogs", "days".
				var z := false
				if i == n - 1 and i > 0 and w[i - 1] != "s" and not out.is_empty():
					var p_ph: String = out[-1][0]
					var p1 := w[i - 1]
					var p2 := w[i - 2] if i > 1 else ""
					z = p_ph in VOICED_CONS or p1 in "yw" or (p1 in "eo" and _is_vowel_letter(p2))
				out.append([("z" if z else "s"), i + 1])
			_:
				if LETTER_PHONES.has(c):
					for ph in LETTER_PHONES[c]:
						out.append([ph, i + 1])
		i += 1
	return out


## Splits a gibberish token like "gr", "ai" or "sh" into sound names.
static func _token_phones(tok: String) -> Array:
	if P.TABLE.has(tok):
		return [tok]
	match tok:
		"ch": return ["t", "sh"]
		"j": return ["d", "zh"]
	var out: Array = []
	for c in tok:
		if LETTER_PHONES.has(c):
			out.append_array(LETTER_PHONES[c])
	return out


static func estimate_syllables(w: String) -> int:
	if _is_ascii_word(w):
		var count := 0
		var prev_vowel := false
		for c in w:
			var v := _is_vowel_letter(c)
			if v and not prev_vowel:
				count += 1
			prev_vowel = v
		if count > 1 and w.ends_with("e") and not w.ends_with("le"):
			count -= 1
		return clampi(count, 1, 8)
	var wide := 0
	var other := 0
	for i in w.length():
		if w.unicode_at(i) >= 0x2E80:
			wide += 1
		else:
			other += 1
	return clampi(wide + ceili(other / 2.5), 1, 8)


static func _pick(list: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if list.is_empty():
		return ""
	return list[rng.randi() % list.size()]


## Returns an array of {ph, rev} for one word, then marks syllables.
static func _word_phones(w: Dictionary, voice: BlabberVoice, sentence_first: bool) -> Array:
	var text: String = w.text
	var idx: Array = w.idx
	var lower := text.to_lower()
	var out: Array = []
	var phonetic := voice.mode == BlabberVoice.Mode.PHONETIC
	if not phonetic and voice.speak_names and not sentence_first and text[0] != lower[0]:
		phonetic = true
	if phonetic and _is_ascii_word(lower):
		var pos := 0
		while pos < lower.length():
			var c := lower[pos]
			if c >= "0" and c <= "9":
				for pe in g2p(DIGIT_WORDS[int(c)]):
					out.append({"ph": pe[0], "rev": idx[pos] + 1})
				pos += 1
				continue
			var start := pos
			while pos < lower.length() and not (lower[pos] >= "0" and lower[pos] <= "9"):
				pos += 1
			for pe in g2p(lower.substr(start, pos - start)):
				out.append({"ph": pe[0], "rev": idx[start + pe[1] - 1] + 1})
	else:
		var nsyl := estimate_syllables(lower)
		var grng := RandomNumberGenerator.new()
		grng.seed = hash(lower) + voice.language_seed * 104729
		var ons := voice.onsets.split(" ", false)
		var vows := voice.vowels.split(" ", false)
		var cods := voice.codas.split(" ", false)
		if vows.is_empty():
			vows = PackedStringArray(["a"])
		var n := idx.size()
		for s in nsyl:
			var phs: Array = []
			if grng.randf() < voice.onset_chance:
				phs.append_array(_token_phones(_pick(ons, grng)))
			phs.append_array(_token_phones(_pick(vows, grng)))
			if grng.randf() < voice.coda_chance:
				phs.append_array(_token_phones(_pick(cods, grng)))
			var rev: int = idx[clampi(int(ceil(float(s + 1) * n / nsyl)) - 1, 0, n - 1)] + 1
			for ph in phs:
				out.append({"ph": ph, "rev": rev})
	# Mark syllable nuclei. A vowel right after a vowel is a glide (as in "ai").
	var prev_vowel := false
	for pd in out:
		var v := P.is_vowel_phone(pd.ph)
		pd.syl = v and not prev_vowel
		pd.off = v and prev_vowel
		prev_vowel = v
	return out


# --- Step 4: melody, timing and segments --------------------------------------

static func _dyn(voice: BlabberVoice, emo: Dictionary) -> Dictionary:
	return {
		"br": clampf(voice.breathiness + emo.get("breath", 0.0), 0.0, 1.0),
		"ro": clampf(voice.roughness + emo.get("rough", 0.0), 0.0, 1.0),
		"gr": clampf(voice.growl + emo.get("growl", 0.0), 0.0, 1.0),
		"te": clampf(voice.tenseness + emo.get("tense", 0.0), 0.0, 1.0),
		"ji": maxf(voice.jitter + emo.get("jitter", 0.0), 0.0),
		"vd": maxf(voice.vibrato_depth + emo.get("vib_depth", 0.0), 0.0),
		"vr": float(emo.get("vib_rate", voice.vibrato_rate)),
		"vo": clampf(voice.voicing + emo.get("voicing", 0.0), 0.0, 1.0),
	}


static func _seg(d: float, f: Array, p0: float, p1: float, amp: float, rev: int, dyn: Dictionary) -> Dictionary:
	var s := dyn.duplicate()
	s.merge({"d": d, "f": f, "v": 0.0, "asp": 0.0, "fr": 0.0, "nf": 3000.0, "nq": 1.0,
		"p0": p0, "p1": p1, "a": amp, "m": 0.0, "rev": rev, "syl": false, "word": "", "fast": false, "ph": ""}, true)
	return s


static func _silence(d: float, rev: int, segs: Array) -> Dictionary:
	if segs.is_empty():
		return _seg(d, P.SCHWA, 120.0, 120.0, 0.0, rev, _dyn(BlabberVoice.new(), {}))
	var prev: Dictionary = segs[-1]
	var s := prev.duplicate()
	s.merge({"d": d, "v": 0.0, "asp": 0.0, "fr": 0.0, "m": 0.0, "rev": rev, "syl": false,
		"word": "", "fast": false, "p0": prev.p1, "p1": prev.p1, "ph": ""}, true)
	return s


static func _push(segs: Array, s: Dictionary) -> void:
	if not segs.is_empty():
		s.rev = maxi(s.rev, segs[-1].rev)
	segs.append(s)


static func _st(semis: float) -> float:
	return pow(2.0, semis / 12.0)


static func _build_sentence(s: Dictionary, voice: BlabberVoice, rng: RandomNumberGenerator, segs: Array) -> void:
	var words: Array = []
	for tok in s.tokens:
		if tok.t == "word":
			words.append(tok)
	var total_syl := 0
	for wi in words.size():
		var w: Dictionary = words[wi]
		w.phones = _word_phones(w, voice, wi == 0)
		w.nsyl = 0
		for pd in w.phones:
			if pd.syl:
				w.nsyl += 1
		total_syl += w.nsyl
	var kind: String = s.end
	var syl_k := 0
	var word_n := 0
	var last_speed := voice.speed
	var tokens: Array = s.tokens
	for ti in tokens.size():
		var tok: Dictionary = tokens[ti]
		match tok.t:
			"pause":
				_push(segs, _silence(tok.s, tok.i, segs))
			"punct":
				_push(segs, _silence(PUNCT_PAUSE[tok.c] * voice.pause_scale / last_speed, tok.i + 1, segs))
			"word":
				var next_is_word: bool = ti + 1 < tokens.size() and tokens[ti + 1].t == "word"
				last_speed = _emit_word(tok, voice, rng, segs, kind, syl_k, total_syl,
					word_n == 0, word_n == words.size() - 1, next_is_word)
				syl_k += tok.nsyl
				word_n += 1


## Adds one word's segments. Returns the word's effective speed.
static func _emit_word(w: Dictionary, voice: BlabberVoice, rng: RandomNumberGenerator, segs: Array,
		kind: String, syl_k: int, total_syl: int, is_first: bool, is_last: bool, next_is_word: bool) -> float:
	var st: Dictionary = w.st
	var emo := BlabberVoice.emotion(st.emote)
	var speed: float = maxf(voice.speed * st.speed * emo.get("speed", 1.0), 0.05)
	var inton: float = voice.intonation * emo.get("intonation", 1.0)
	var base: float = voice.pitch * st.pitch * emo.get("pitch", 1.0)
	var word_amp: float = st.volume * emo.get("volume", 1.0)
	var dyn := _dyn(voice, emo)
	var text: String = w.text
	var lower := text.to_lower()
	var is_func := P.FUNCTION_WORDS.has(lower)
	var is_caps := text.length() > 1 and text == text.to_upper() and text != lower
	var word_off := (rng.randf() * 2.0 - 1.0) * voice.pitch_variation
	var phones: Array = w.phones
	var nsyl: int = w.nsyl
	var art := voice.articulation

	# Melody for each syllable.
	var syl_i := 0
	var last_v = null
	for pd in phones:
		if pd.off and last_v != null:
			pd.p0 = last_v.p1; pd.p1 = last_v.p1; pd.amp = last_v.amp; pd.dm = last_v.dm * 0.6
			continue
		if not pd.syl:
			continue
		var t := float(syl_k + syl_i) / maxf(1.0, total_syl - 1.0)
		var semis := inton * (0.35 - 0.7 * t) + word_off + (rng.randf() * 2.0 - 1.0) * voice.pitch_variation * 0.4
		var stressed := syl_i == 0 and not is_func
		var dm := 1.0
		var amp := 0.82
		if stressed:
			semis += inton * 0.35
			dm = 1.2
			amp = 1.0
		if is_func:
			semis -= inton * 0.15
			dm = 0.75
		if kind == "!":
			semis += inton * 0.3 + (inton * 0.4 if stressed and is_first else 0.0)
			amp *= 1.12
		if is_caps:
			semis += inton * 0.5 + 1.0
			amp *= 1.3
			dm *= 1.15
		var p0 := base * _st(semis)
		var p1 := p0
		if is_last and syl_i == nsyl - 1:
			dm *= 1.35
			if kind == "?":
				p1 = p0 * _st(inton * 1.0 + 1.0)
			elif kind != "":
				p1 = p0 * _st(-inton * 0.6)
		pd.p0 = p0; pd.p1 = p1; pd.amp = amp; pd.dm = dm
		last_v = pd
		syl_i += 1

	# Consonants borrow pitch and mouth shape from the nearest vowel.
	var default_p := base * _st(word_off)
	for j in phones.size():
		var pd: Dictionary = phones[j]
		if pd.has("p0"):
			continue
		var ctx = null
		for k in range(j + 1, phones.size()):
			if phones[k].has("p0") and P.is_vowel_phone(phones[k].ph):
				ctx = phones[k]; break
		if ctx == null:
			for k in range(j - 1, -1, -1):
				if phones[k].has("p0") and P.is_vowel_phone(phones[k].ph):
					ctx = phones[k]; break
		pd.p0 = ctx.p0 if ctx else default_p
		pd.p1 = pd.p0
		pd.amp = ctx.amp if ctx else 0.9
		pd.dm = 1.0
		pd.ctx_f = P.TABLE[ctx.ph].f if ctx else P.SCHWA

	var first_seg := segs.size()
	for j in phones.size():
		var pd: Dictionary = phones[j]
		var tbl: Dictionary = P.TABLE[pd.ph]
		var a: float = pd.amp * word_amp
		var rev: int = pd.rev
		var p0: float = pd.p0
		var p1: float = pd.p1
		var next_vowel: bool = j + 1 < phones.size() and P.is_vowel_phone(phones[j + 1].ph)
		var seg_count := segs.size()
		match tbl.k:
			Kind.VOWEL:
				var sg := _seg(0.085 * pd.dm / speed, tbl.f, p0, p1, a, rev, dyn)
				sg.v = 1.0; sg.m = tbl.mouth; sg.syl = pd.syl
				_push(segs, sg)
			Kind.NASAL:
				var sg := _seg(0.065 / speed, tbl.f, p0, p1, a * 0.8, rev, dyn)
				sg.v = 1.0; sg.m = 0.05
				_push(segs, sg)
			Kind.LIQUID:
				var sg := _seg(0.05 / speed, tbl.f, p0, p1, a * 0.85, rev, dyn)
				sg.v = 1.0; sg.m = 0.35
				_push(segs, sg)
			Kind.PLOSIVE:
				var voiced: bool = tbl.voiced
				var cl := _seg(0.045 * (0.5 + 0.5 * art) / speed, pd.ctx_f, p0, p1, a, rev, dyn)
				cl.v = lerpf(0.6, 0.25 if voiced else 0.0, art); cl.m = 0.05
				_push(segs, cl)
				var bu := _seg(0.012 / speed, pd.ctx_f, p0, p1, a, rev, dyn)
				bu.fr = tbl.amp * art; bu.nf = tbl.nf; bu.nq = tbl.nq; bu.fast = true; bu.m = 0.2
				bu.v = 0.3 if voiced else 0.0
				_push(segs, bu)
				if not voiced and next_vowel and art > 0.1:
					var asp := _seg(0.028 * art / speed, pd.ctx_f, p0, p1, a, rev, dyn)
					asp.asp = 0.45 * art; asp.m = 0.3
					_push(segs, asp)
			Kind.FRICATIVE:
				var sg := _seg(0.075 * (0.5 + 0.5 * art) / speed, pd.ctx_f, p0, p1, a, rev, dyn)
				sg.fr = tbl.amp * art * (voice.sibilance if tbl.get("sib", false) else 1.0)
				sg.nf = tbl.nf; sg.nq = tbl.nq; sg.m = 0.2
				sg.v = 0.45 if tbl.voiced else (1.0 - art) * 0.5
				_push(segs, sg)
			Kind.ASPIRATE:
				var sg := _seg(0.055 / speed, pd.ctx_f, p0, p1, a, rev, dyn)
				sg.asp = 0.5 * art + 0.1; sg.v = (1.0 - art) * 0.5; sg.m = 0.5
				_push(segs, sg)
		for q in range(seg_count, segs.size()):
			segs[q].ph = pd.ph
	if segs.size() > first_seg:
		segs[first_seg].word = text
	if next_is_word and voice.word_gap > 0.0:
		_push(segs, _silence(voice.word_gap / speed, w.idx[-1] + 1, segs))
	return speed
