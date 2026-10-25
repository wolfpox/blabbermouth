extends SceneTree
## Checks the letters-to-sounds rules on common words. Exits with code 1 on failure.
## godot --headless --path . -s tools/test_g2p.gd

const P := preload("res://addons/blabbermouth/blabber_phonemes.gd")

const EXPECT := {
	"the": "dh uh", "was": "w uh z", "one": "w uh n", "make": "m e i k", "time": "t a i m",
	"home": "h o u m", "cute": "k y u t", "use": "y u s", "go": "g o u", "hello": "h e l o u",
	"my": "m a i", "fly": "f l a i", "happy": "h ae p i", "dogs": "d o g z", "cats": "k ae t s",
	"days": "d e i z", "goes": "g o u z", "kiss": "k ih s", "walked": "w o k t",
	"played": "p l e i d", "wanted": "w o n t ih d", "makes": "m e i k s", "boxes": "b o k s ih z",
	"changes": "t sh e i n d zh ih z", "nation": "n e i sh uh n", "action": "ae k sh uh n",
	"vision": "v ih zh uh n", "picture": "p ih k t sh er", "famous": "f a m uh s",
	"house": "h a u s", "all": "o l", "talk": "t o k", "want": "w o n t", "watch": "w o t sh",
	"war": "w o r", "car": "k a r", "large": "l a r d zh", "page": "p e i d zh",
	"bridge": "b r ih d zh", "little": "l ih t uh l", "table": "t e i b uh l", "find": "f a i n d",
	"old": "o u l d", "down": "d a u n", "know": "n o u", "known": "n o u n", "that": "dh ae t",
	"mother": "m uh dh er", "thing": "th ih ng", "earth": "er th", "year": "y i r",
	"music": "m y u s ih k", "active": "ae k t ih v", "five": "f a i v", "climb": "k l ih m",
	"don't": "d o u n t", "it's": "ih t s", "invasion": "ih n v e i zh uh n",
}


func _init() -> void:
	var failures := 0
	for w in EXPECT:
		var got := _say(w)
		if got != EXPECT[w]:
			failures += 1
			print("FAIL: %s -> %s (expected %s)" % [w, got, EXPECT[w]])
	# Every exception must use real sounds, and positions must stay inside the word.
	for w in BlabberParser.EXCEPTIONS:
		for ph in BlabberParser.EXCEPTIONS[w].split(" ", false):
			if not P.TABLE.has(ph):
				failures += 1
				print("FAIL: exception '%s' uses unknown sound '%s'" % [w, ph])
	for w in EXPECT.keys() + BlabberParser.EXCEPTIONS.keys():
		for pe in BlabberParser.g2p(w):
			if pe[1] < 1 or pe[1] > w.length() or not P.TABLE.has(pe[0]):
				failures += 1
				print("FAIL: %s gives bad sound %s" % [w, pe])
	# Words ending in two consonants ("six", "cats") used to cut the line short.
	var line := "I have six cats, two dogs and a fox."
	var plan := BlabberParser.build(line, BlabberVoice.preset("man"))
	var reached: int = plan.segments[-1].rev
	if reached != plan.visible:
		failures += 1
		print("FAIL: phonetic line stops early (%d of %d chars)" % [reached, plan.visible])
	print("g2p tests: ", "all passed" if failures == 0 else "%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _say(w: String) -> String:
	var phs := PackedStringArray()
	for pe in BlabberParser.g2p(w):
		phs.append(pe[0])
	return " ".join(phs)
