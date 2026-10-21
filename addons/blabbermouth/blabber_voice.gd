@tool
class_name BlabberVoice
extends Resource
## A character voice. Save one as a .tres and share it between characters.
##
## The two most important settings are [member pitch] (how fast the vocal
## cords buzz) and [member formant_scale] (how big the throat is). Moving
## them separately is what makes a voice sound small, big, male or female
## instead of just sped up or slowed down.

enum Mode {
	## Each word becomes made-up syllables. The same word always sounds the same.
	GIBBERISH,
	## Follows the letters of the text, so it sounds like mumbled speech.
	PHONETIC,
}

const PRESET_NAMES := ["critter", "child", "woman", "man", "elder", "goblin", "monster", "robot"]

## Emotion modifiers. Multipliers: pitch, intonation, speed, volume.
## Additions: breath, rough, growl, tense, jitter, vib_depth, voicing.
## vib_rate replaces the voice's vibrato rate.
const EMOTIONS := {
	"neutral": {},
	"happy": {"pitch": 1.08, "intonation": 1.4, "speed": 1.08, "volume": 1.05, "tense": 0.1},
	"excited": {"pitch": 1.14, "intonation": 1.7, "speed": 1.2, "volume": 1.15, "tense": 0.15},
	"angry": {"pitch": 0.96, "intonation": 1.25, "speed": 1.12, "volume": 1.25, "rough": 0.25, "growl": 0.15, "tense": 0.3},
	"sad": {"pitch": 0.9, "intonation": 0.5, "speed": 0.78, "volume": 0.8, "breath": 0.25, "tense": -0.2},
	"scared": {"pitch": 1.15, "intonation": 1.3, "speed": 1.25, "jitter": 0.03, "vib_depth": 0.5, "vib_rate": 9.0, "breath": 0.15},
	"whisper": {"voicing": -1.0, "breath": 0.9, "volume": 1.3, "intonation": 0.6},
	"shout": {"pitch": 1.2, "volume": 1.4, "tense": 0.4, "intonation": 1.3, "speed": 0.95, "rough": 0.1},
}

@export_group("Pitch")
## How fast the vocal cords buzz. Men ~110, women ~210, critters 500+.
@export_range(30.0, 1500.0, 1.0, "suffix:Hz") var pitch := 120.0
## How much the melody rises and falls across a sentence.
@export_range(0.0, 12.0, 0.1, "suffix:semitones") var intonation := 4.0
## Random pitch wobble per word and syllable. High = chirpy and sing-song.
@export_range(0.0, 8.0, 0.1, "suffix:semitones") var pitch_variation := 1.0
@export_range(0.0, 2.0, 0.01, "suffix:semitones") var vibrato_depth := 0.0
@export_range(0.0, 12.0, 0.1, "suffix:Hz") var vibrato_rate := 5.5

@export_group("Body")
## Throat size. 1.0 = adult man, 1.17 = woman, 1.3 = child, 2.0 = tiny creature, 0.65 = giant.
@export_range(0.4, 2.5, 0.01) var formant_scale := 1.0
## Low = soft and dark, high = pressed and bright.
@export_range(0.0, 1.0, 0.01) var tenseness := 0.5
## Air in the voice. 1.0 with voicing 0 is a whisper.
@export_range(0.0, 1.0, 0.01) var breathiness := 0.1
## Rasp and vocal fry. Good for old, sick or gruff characters.
@export_range(0.0, 1.0, 0.01) var roughness := 0.0
## Rumble and distortion for monsters.
@export_range(0.0, 1.0, 0.01) var growl := 0.0
## Random pitch unsteadiness per vocal-cord cycle.
@export_range(0.0, 0.1, 0.001) var jitter := 0.01
## Random loudness unsteadiness per vocal-cord cycle.
@export_range(0.0, 0.5, 0.01) var shimmer := 0.05
## 0 = whisper, 1 = fully voiced.
@export_range(0.0, 1.0, 0.01) var voicing := 1.0

@export_group("Delivery")
@export_range(0.3, 3.0, 0.01) var speed := 1.0
## How crisp consonants are. 0 = a hum, 1 = clear consonants.
@export_range(0.0, 1.0, 0.01) var articulation := 0.75
## Short gap between words, in seconds.
@export_range(0.0, 0.2, 0.005, "suffix:s") var word_gap := 0.03
## Scales pauses at commas and full stops.
@export_range(0.0, 3.0, 0.01) var pause_scale := 1.0
@export_range(0.0, 2.0, 0.01) var volume := 0.8

@export_group("Language")
@export var mode := Mode.GIBBERISH
## Gibberish onsets, space separated. Repeat a sound to make it more common.
## Clusters like "gr" are fine. Sounds: b d g p t k m n ng l r w y f v th s z sh zh h ch j.
@export var onsets := "b d g k m n l r s t p w h y v z f sh"
## Gibberish vowels: a ae e i ih o u uh er. Two-letter combos like "ai" make a glide.
@export var vowels := "a e i o u a e"
## Gibberish syllable endings.
@export var codas := "n m s k t r l"
@export_range(0.0, 1.0, 0.01) var onset_chance := 0.85
@export_range(0.0, 1.0, 0.01) var coda_chance := 0.2
## Change this to give a species its own "language" with the same sounds.
@export var language_seed := 0
## In gibberish mode, speak capitalized names phonetically so they stay recognizable.
@export var speak_names := false

@export_group("Effects")
## Ring modulation for robots. 0 = off.
@export_range(0.0, 400.0, 1.0, "suffix:Hz") var ring_mod_hz := 0.0
@export_range(0.0, 1.0, 0.01) var ring_mod_mix := 0.0


static func emotion(emotion_name: String) -> Dictionary:
	return EMOTIONS.get(emotion_name.to_lower(), {})


## Returns a new voice built from one of PRESET_NAMES.
static func preset(preset_name: String) -> BlabberVoice:
	var v := BlabberVoice.new()
	v.resource_name = preset_name
	match preset_name:
		"critter":
			v.pitch = 620.0; v.formant_scale = 1.9; v.intonation = 7.0; v.pitch_variation = 3.0
			v.speed = 1.35; v.articulation = 0.5; v.breathiness = 0.05; v.tenseness = 0.65
			v.jitter = 0.01; v.word_gap = 0.04
			v.onsets = "p t k m w b n p"; v.vowels = "i i e a u i"; v.codas = "p k"; v.coda_chance = 0.1
			v.language_seed = 11
		"child":
			v.pitch = 290.0; v.formant_scale = 1.32; v.intonation = 6.0; v.pitch_variation = 1.6
			v.speed = 1.1; v.articulation = 0.7; v.breathiness = 0.15; v.tenseness = 0.45
		"woman":
			v.pitch = 215.0; v.formant_scale = 1.17; v.intonation = 5.0; v.pitch_variation = 1.2
			v.articulation = 0.75; v.breathiness = 0.2; v.tenseness = 0.45
		"man":
			v.pitch = 112.0; v.formant_scale = 1.0; v.intonation = 4.0; v.pitch_variation = 1.0
			v.speed = 0.95; v.articulation = 0.8; v.breathiness = 0.08; v.tenseness = 0.5
		"elder":
			v.pitch = 135.0; v.formant_scale = 1.02; v.intonation = 3.0; v.pitch_variation = 1.0
			v.speed = 0.8; v.articulation = 0.6; v.breathiness = 0.3; v.roughness = 0.25
			v.jitter = 0.04; v.shimmer = 0.15; v.vibrato_depth = 0.35; v.vibrato_rate = 5.5
			v.tenseness = 0.35
		"goblin":
			v.pitch = 260.0; v.formant_scale = 1.45; v.intonation = 6.0; v.pitch_variation = 2.5
			v.speed = 1.3; v.articulation = 0.85; v.roughness = 0.35; v.growl = 0.2; v.tenseness = 0.75
			v.onsets = "g k sh n t z r gr sk"; v.vowels = "i e a ih"; v.codas = "k sh t z"; v.coda_chance = 0.4
			v.language_seed = 23
		"monster":
			v.pitch = 58.0; v.formant_scale = 0.68; v.intonation = 3.0; v.pitch_variation = 1.5
			v.speed = 0.8; v.articulation = 0.5; v.breathiness = 0.1; v.roughness = 0.6; v.growl = 0.7
			v.tenseness = 0.8; v.volume = 0.9
			v.onsets = "g gr b d k kr r m z"; v.vowels = "o u a uh o"; v.codas = "g k r m"; v.coda_chance = 0.35
			v.language_seed = 31
		"robot":
			v.pitch = 100.0; v.formant_scale = 1.05; v.intonation = 0.0; v.pitch_variation = 2.0
			v.speed = 1.05; v.articulation = 0.95; v.breathiness = 0.0; v.tenseness = 1.0
			v.jitter = 0.0; v.shimmer = 0.0; v.word_gap = 0.05
			v.ring_mod_hz = 70.0; v.ring_mod_mix = 0.6
			v.onsets = "b d t k p m n z"; v.vowels = "i e o a"; v.language_seed = 42
		_:
			push_warning("BlabberVoice: unknown preset '%s', using 'man'." % preset_name)
			return preset("man")
	return v
