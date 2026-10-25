class_name BlabberPhonemes
extends RefCounted
## Sound tables used by the parser.
##
## Formant frequencies ("f") are for an adult male reference voice.
## Each voice scales them with BlabberVoice.formant_scale.

enum Kind { VOWEL, NASAL, LIQUID, PLOSIVE, FRICATIVE, ASPIRATE }

const SCHWA := [500.0, 1500.0, 2500.0, 3500.0]

const TABLE := {
	# Vowels. mouth = how open the jaw is (drives lip-sync).
	"a":  {"k": Kind.VOWEL, "f": [730.0, 1090.0, 2440.0, 3400.0], "mouth": 1.0},
	"ae": {"k": Kind.VOWEL, "f": [660.0, 1720.0, 2410.0, 3400.0], "mouth": 0.9},
	"e":  {"k": Kind.VOWEL, "f": [530.0, 1840.0, 2480.0, 3500.0], "mouth": 0.7},
	"i":  {"k": Kind.VOWEL, "f": [270.0, 2290.0, 3010.0, 3700.0], "mouth": 0.35},
	"ih": {"k": Kind.VOWEL, "f": [390.0, 1990.0, 2550.0, 3600.0], "mouth": 0.45},
	"o":  {"k": Kind.VOWEL, "f": [570.0, 840.0, 2410.0, 3400.0], "mouth": 0.8},
	"u":  {"k": Kind.VOWEL, "f": [300.0, 870.0, 2240.0, 3300.0], "mouth": 0.3},
	"uh": {"k": Kind.VOWEL, "f": [520.0, 1190.0, 2390.0, 3400.0], "mouth": 0.6},
	"er": {"k": Kind.VOWEL, "f": [490.0, 1350.0, 1690.0, 3300.0], "mouth": 0.5},

	# Voiced resonant consonants.
	"m":  {"k": Kind.NASAL, "f": [270.0, 1100.0, 2300.0, 3300.0]},
	"n":  {"k": Kind.NASAL, "f": [270.0, 1500.0, 2500.0, 3400.0]},
	"ng": {"k": Kind.NASAL, "f": [270.0, 2000.0, 2600.0, 3400.0]},
	"l":  {"k": Kind.LIQUID, "f": [360.0, 1300.0, 2700.0, 3500.0]},
	"r":  {"k": Kind.LIQUID, "f": [420.0, 1250.0, 1650.0, 3300.0]},
	"w":  {"k": Kind.LIQUID, "f": [300.0, 650.0, 2200.0, 3300.0]},
	"y":  {"k": Kind.LIQUID, "f": [280.0, 2200.0, 3000.0, 3700.0]},

	# Stops: a closure, then a noise burst at nf Hz.
	"b":  {"k": Kind.PLOSIVE, "voiced": true,  "nf": 800.0,  "nq": 1.2, "amp": 0.45},
	"d":  {"k": Kind.PLOSIVE, "voiced": true,  "nf": 3500.0, "nq": 1.5, "amp": 0.5},
	"g":  {"k": Kind.PLOSIVE, "voiced": true,  "nf": 1900.0, "nq": 2.0, "amp": 0.5},
	"p":  {"k": Kind.PLOSIVE, "voiced": false, "nf": 800.0,  "nq": 1.2, "amp": 0.55},
	"t":  {"k": Kind.PLOSIVE, "voiced": false, "nf": 4000.0, "nq": 1.5, "amp": 0.6},
	"k":  {"k": Kind.PLOSIVE, "voiced": false, "nf": 2000.0, "nq": 2.0, "amp": 0.6},

	# Hissy consonants: filtered noise.
	"f":  {"k": Kind.FRICATIVE, "voiced": false, "nf": 5500.0, "nq": 0.6, "amp": 0.22},
	"v":  {"k": Kind.FRICATIVE, "voiced": true,  "nf": 5500.0, "nq": 0.6, "amp": 0.18},
	"th": {"k": Kind.FRICATIVE, "voiced": false, "nf": 6000.0, "nq": 0.7, "amp": 0.18},
	"dh": {"k": Kind.FRICATIVE, "voiced": true,  "nf": 6000.0, "nq": 0.7, "amp": 0.12}, # "the"
	# "s" is the most common hiss, so it is kept wide and moderate: a narrow
	# band here turns into a piercing whistle that tires the ear.
	"s":  {"k": Kind.FRICATIVE, "voiced": false, "nf": 6500.0, "nq": 1.2, "amp": 0.36, "sib": true},
	"z":  {"k": Kind.FRICATIVE, "voiced": true,  "nf": 6500.0, "nq": 1.2, "amp": 0.28, "sib": true},
	"sh": {"k": Kind.FRICATIVE, "voiced": false, "nf": 2800.0, "nq": 2.0, "amp": 0.6, "sib": true},
	"zh": {"k": Kind.FRICATIVE, "voiced": true,  "nf": 2800.0, "nq": 2.0, "amp": 0.48, "sib": true},

	# Breath through the shape of the next vowel.
	"h":  {"k": Kind.ASPIRATE},
}

## Common short words that get no stress and are spoken quicker.
const FUNCTION_WORDS := {
	"a": true, "an": true, "the": true, "of": true, "to": true, "and": true, "or": true,
	"in": true, "on": true, "at": true, "is": true, "it": true, "as": true, "be": true,
	"by": true, "for": true, "with": true, "from": true, "that": true, "this": true,
	"but": true, "are": true, "was": true, "i": true, "you": true, "he": true, "she": true,
	"we": true, "they": true, "my": true, "your": true, "his": true, "her": true,
	"its": true, "our": true, "me": true, "him": true, "us": true, "them": true,
	"do": true, "so": true, "if": true, "up": true,
}


static func is_vowel_phone(ph: String) -> bool:
	return TABLE.has(ph) and TABLE[ph].k == Kind.VOWEL
