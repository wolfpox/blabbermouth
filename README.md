# Blabbermouth

A text-to-mumble voice engine for Godot 4.3+. It turns dialogue text into
character "speech" like Animal Crossing, Undertale or The Sims, from squeaky
critters to growling monsters, without any audio files.

Everything is generated in real time by a small formant synthesizer written in
GDScript. One voice costs about 3–6% of one CPU core. You can also record your
own voice (or any sound) and it will talk with that instead.

## Try it in your browser

The demo is a line editor that runs on the web, phones included. Write a
line, select words in the speaker's speech bubble and give them an effect
(shout, whisper, shiver, wave, swell, bounce, droop, jolt, slow, fast, high,
low, pause). The bubble shows the effect and the voice reads it that way.
Switch the voice between the character's synth voice and your own recording,
record real takes of words your game uses (its vocabulary), then export the
line for a game or as a sound file.

**Link:** https://wolfpox.github.io/blabbermouth/ (once Pages is turned on, see below).

### Publishing the web version (one-time setup)

1. Merge into `main`.
2. In the repo on GitHub, open **Settings → Pages** and set **Source** to
   **GitHub Actions**.
3. The **Web build** workflow runs on every push and publishes `main` to the
   link above. Share that link with anyone.

The build is single-threaded, so it works on plain static hosting with no
special headers. In the browser, the microphone and file loading use the
browser's own audio features, so `.m4a` voice memos from phones load too.
The page must be served over `https` for the microphone, which GitHub Pages
does.

To build locally: install Godot 4.7 and its export templates, then run
`godot --headless --path . --export-release "Web" build/web/index.html`
and serve `build/web` with any static web server.

The demo project is made with Godot 4.7. The addon itself works in
Godot 4.3 and later.

## Quick start

1. Copy `addons/blabbermouth` into your project and enable it in
   **Project Settings > Plugins** (needed for `.blab` voice files).
2. Add a `Blabbermouth` node to a character.
3. In the inspector, set **Voice** to a preset from `addons/blabbermouth/voices/`,
   a `.blab` voice file in your project, or a new `BlabberVoice`. Optionally
   set **Label Path** to your dialogue `Label` / `RichTextLabel`.
4. Call it:

```gdscript
$Blabbermouth.speak("Hello there, traveler! [emote=happy]Lovely day, isn't it?")
await $Blabbermouth.finished
```

The label is revealed in sync with the voice (a typewriter effect), so you don't
need a separate timer.

To try it, open this repo as a Godot project and run it. See
[The editor](#the-editor) for what the demo does.

## The editor

The demo (`demo/`) is built around the speech bubble:

- **Line**: the toolbar formats the selected words (or the whole line when
  nothing is selected). Drag across words in the bubble, tap a word, or
  select in the **Words** box. Click the name tag on the bubble to change
  who says the line. Under the bubble, switch between **Synth voice** and
  **My recording**. **How the voice reads it** lists every effect and what
  it does to the voice; **Show tags** shows the tagged text a game gets.
- **Characters**: eight starting characters, each with a voice and a bubble
  style (font, colors, corners, outline, shadow, tail). Add, duplicate,
  rename or delete them, and record a voice for each one.
- **Vocabulary**: words and phrases spoken with real recordings. Add a word,
  record a take or two (or load a sound file), and every line that uses it
  plays one of the takes in the speaker's pitch and size. **Hear** plays it
  as the current character. Each character can switch the vocabulary off.
  **Export vocabulary** saves every word as one `.blab` file for a game.
- **Voices**: save voices on this device and move them between devices.
- **Export**: a `.blab` line file (text, effects and a copy of the speaker,
  font included if you like) for Godot, or a `.wav` that plays anywhere.
  **Open** loads a line file back into the editor.

Your characters and the current line are saved on the device as you work
(`user://editor.json`, and the vocabulary in `user://editor_vocabulary.blab`). The bubble fonts in `demo/fonts/` are open-source
(SIL Open Font License, see `demo/fonts/licenses/`), so exported lines can
carry them.

## Voices

| Preset  | Pitch | Throat size | Character |
|---------|-------|-------------|-----------|
| critter | 620 Hz | 1.9  | Fast, chirpy, squeaky |
| child   | 290 Hz | 1.32 | Bright and bouncy |
| woman   | 215 Hz | 1.17 | Warm, slightly breathy |
| man     | 112 Hz | 1.0  | Steady |
| elder   | 135 Hz | 1.02 | Slow, raspy, shaky |
| goblin  | 260 Hz | 1.45 | Sharp, raspy, quick |
| monster | 58 Hz  | 0.68 | Deep growl |
| robot   | 100 Hz | 1.05 | Flat, metallic |

The two settings that matter most:

- **pitch**: how fast the vocal cords buzz.
- **formant_scale**: how big the throat is. 1.0 is an adult man; higher is
  smaller (woman 1.17, child 1.3, tiny creature 2.0); lower is a giant.

Changing them separately is what makes a voice sound big or small instead
of a sped-up recording. Other settings: intonation, pitch variation, speed,
articulation (hum ↔ crisp consonants), sibilance (how strong s, z and sh
are; lower it if they grate), tenseness, breathiness, roughness
(rasp), growl, jitter, shimmer, vibrato, voicing (0 = whisper) and ring
modulation.

Make a voice in code:

```gdscript
var v := BlabberVoice.preset("goblin")
v.pitch = 300.0
v.growl = 0.4
$Blabbermouth.speak("Mine! All mine!", v)
```

Or tweak it in the demo, then on the **Voices** page press **Save .tres for Godot**.

## Gibberish vs phonetic

- **Phonetic** (default): follows the letters with English spelling rules
  (silent e, "-ed", "-tion", plural "z" and so on, plus a list of common
  irregular words like "the", "one" and "was"), so you can make out the words.
- **Gibberish**: each word becomes made-up syllables built from the
  voice's `onsets`, `vowels` and `codas`. The same word always sounds the same,
  so players start to "learn" words. Change `language_seed` to give a species
  its own language. `speak_names` (on by default) keeps capitalized names
  recognizable.

Any language works. Non-Latin text (Japanese, Russian and others) is spoken as
gibberish with a matching rhythm.

## Your own voice (samples)

Record yourself, a friend, your cat, or load any WAV, OGG or MP3, and the
engine speaks with those sounds instead of the synth.

In the demo, choose **My recording** under the bubble (or **Record their
voice** on the Characters page):

1. Press **Record** and read the nonsense line out loud (or make any noises),
   or press **Load file…**, or drop a file on the window.
2. The recording is cleaned up (silence trimmed, room noise gated, volume
   evened out) and cut into syllables, shown as colored pieces. Cool
   colors are bright "ee" sounds and warm colors are dark "oo" sounds; grey
   pieces have no clear pitch.
3. Tap a piece to hear it. Turn on **Tap removes** to drop coughs and clicks.
4. Press **Use this recording**. It plays at the character's Pitch and Size,
   so one recording can be a tiny critter or a giant. Switch back to the
   synth voice any time; the recording is kept. The **Voices** page saves
   it to the library, recording included (see below).

How it works:

- **Matching sounds.** Each syllable in the text picks a recorded piece with a
  similar brightness, so "ee" words use "ee"-like pieces. The same word always
  picks the same pieces.
- **Pitch and size, separately.** Pieces are re-pitched to follow the
  sentence melody using PSOLA (pitch-synchronous overlap-add). A recording can
  be made higher or lower, or smaller or bigger, without the chipmunk effect.
  `pitch` is the target pitch and `formant_scale` is the size change
  (1.0 = as recorded).
- **Delivery still applies.** Speed, intonation, pauses, emotions and tags all
  work. Growl, rasp and whisper are synth-only for now.

In code:

```gdscript
var importer := BlabberAudioImport.new()
add_child(importer)
var result: Dictionary = await importer.load_file("res://voices/me.wav")
var voice := BlabberVoice.preset("man")
voice.sample_bank = BlabberSampleBank.from_samples(result.samples, result.rate)
voice.pitch = voice.sample_bank.reference_pitch()
voice.formant_scale = 1.0
$Blabbermouth.speak("Hey! Over here!", voice)
```

`BlabberRecorder` records from the microphone (`start()`, then `stop()` or the
`stopped` signal), and its result goes into `from_samples()` the same way.

Notes:

- **Web exports:** `BlabberWeb` handles recording and file picking in the
  browser. `BlabberRecorder` uses it automatically. For files, call
  `BlabberWeb.place_file_input(your_button)` every frame. It lays an
  invisible file input over your button, because browsers only open a file
  picker from a real tap. Then watch `BlabberWeb.state()`. Set
  `audio/general/default_playback_type.web` to *Stream* (this project does),
  so voices play through Godot's mixer.
- **Microphone:** turn on *Project Settings > Audio > Driver > Enable Input*
  (this project already has it on). On Android, tick the `RECORD_AUDIO`
  permission in the export preset. On iOS, add a microphone usage
  description.
- **File types:** WAV loads instantly. On Godot 4.3, OGG and MP3 take as long
  as the clip to decode, because they are played silently through a capture
  bus. Newer Godot versions decode them instantly. Phone voice-memo apps
  often save `.m4a`, which Godot can't read, so record in the app instead or
  convert the file first.
- Recordings are capped at 30 seconds. Use 5–15 seconds of varied syllables
  for the best results.

## Vocabulary (real recorded words)

Some words should sound real every time: a greeting, a name, a catchphrase,
the words of an invented language. Put them in a **vocabulary**, record one
or more **takes** of each, and whenever a line uses the word the voice plays
one of its takes instead of synthesizing it. The rest of the line is spoken
as usual, so you only record the words that matter.

The takes are still shaped by the line:

- **Pitch and size**: a take moves to the speaker's pitch and throat size,
  so one recording can be said by a critter, a woman or a monster. It keeps
  its own rise and fall, and follows the sentence melody on top (as much as
  the voice's `sample_melody` says) and ends higher on a question.
- **Speed**: the voice's speed, `[speed]`, slow and fast stretch or squeeze
  the take without changing its pitch.
- **Effects**: shout, whisper, high, low, `[pitch]`, `[volume]`, emotions,
  shiver (vibrato), wave, swell, bounce, droop and jolt all apply. Jolt and
  gruff voices add rasp and growl, and the robot's ring modulation applies too.
- **Variety**: with more than one take, a line never plays the same take
  twice in a row. The same line always picks the same takes, so baked audio
  doesn't change.
- **Phrases** of up to four words ("thank you", "good morning") work too.
  Matching ignores case and punctuation, but punctuation between words
  splits a phrase ("thank, you" isn't "thank you").

Turn off `fit_to_voice` and takes keep the recorded voice: only what the line
adds (effects, tags, melody) changes them. Takes are cut to 6 seconds, and a
word has up to 8 takes. A take without a clear pitch (a whisper, a bark)
can't follow the melody, so it is moved as a whole instead.

In the demo, open **Vocabulary**: add a word, press **Record a take** and say
it (recording stops by itself when you go quiet), or **Load file…**. The line
page lists the line's recorded words under **How the voice reads it**.

In code:

```gdscript
var vocab := BlabberVocabulary.new()
vocab.add_take("hello", samples, 48000)        # from BlabberRecorder or BlabberAudioImport
vocab.add_take("hello", other_samples, 48000)  # a second take, for variety
vocab.add_take("thank you", more_samples, 48000)

var voice := BlabberVoice.preset("goblin")
voice.vocabulary = vocab                     # share it between as many voices as you like
$Blabbermouth.speak("Hello! [shout]Thank you![/shout]", voice)
```

Save it with `vocab.write("user://words.blab")` and read it back with
`BlabberVocabulary.read()`. With the plugin enabled, a vocabulary `.blab`
file in your project imports as a `BlabberVocabulary`: set it as a voice's
**Vocabulary** in the inspector, or load it in code:

```gdscript
var voice: BlabberVoice = preload("res://voices/goblin.blab").duplicate()
voice.vocabulary = preload("res://voices/goblin_words.blab")
```

A voice file keeps its vocabulary, and a line file keeps the takes of the
words that line uses, so an exported line sounds the same in any game.
`BlabberParser.recorded_words(text, voice)` lists which words of a line will
be recorded ones.

## Saving and sharing voices

Voices are saved as `.blab` files: plain JSON text with the settings and,
for recorded voices, the recording (and a vocabulary's takes, if it has
one). A `.blab` file can't contain code, so
it's safe to open one someone else made. Don't share `.tres` or `.res`
files with people you don't trust: Godot resources can run code when loaded.

In the demo, the **Voices** page saves, opens, renames and deletes voices
on this device. To move a voice to another device or browser, **Export**
it, send the file however you like, and **Import** it on the other side
(on desktop you can also drop a `.blab` file on the window).

Where saved voices live:

| Running as | Saved voices are kept | Gone when |
|------------|-----------------------|-----------|
| Desktop app | `user://voices/` (a normal folder) | You delete them |
| Android app | The app's private storage | The app is uninstalled |
| Web page (any device) | The browser's storage for this site | Site data is cleared, or a private window closes |

On the web each browser keeps its own voices, so Chrome on your phone and
Firefox on your laptop don't see each other's. The demo asks the browser
to keep its storage (`navigator.storage.persist()`), so Safari doesn't
clear it after a week without visits.

### Using a voice file in your game

With the plugin enabled, put the `.blab` file anywhere in your project
(for example `res://voices/`). Godot imports it as a voice: drag it onto a
Blabbermouth node's **Voice**, or load it in code. It's included in
exported games like any other asset. To update the voice, replace the
`.blab` file and everything using it picks up the change.

```gdscript
$Announcer.voice = preload("res://voices/Ring announcer.blab")
```

A recording made at one pitch can play several characters. Tweak a copy
in code:

```gdscript
var color_guy: BlabberVoice = preload("res://voices/Ring announcer.blab").duplicate()
color_guy.pitch *= 0.85
color_guy.formant_scale = 0.9   # a bigger throat
```

### In code

```gdscript
# Library on this device (user://voices/).
BlabberLibrary.save(voice, "Grumpy goblin")
for entry in BlabberLibrary.list():   # {name, path, modified, has_recording}
	print(entry.name)
var result := BlabberLibrary.open(BlabberLibrary.path_for("Grumpy goblin"))
if result.ok:
	$Blabbermouth.voice = result.voice

# Any file outside the project, or bytes (for downloads and uploads in web
# exports). For .blab files inside the project, use load() as shown above.
BlabberVoiceFile.write(voice, "user://goblin.blab", "Grumpy goblin")
var loaded := BlabberVoiceFile.read("user://goblin.blab")
var bytes := BlabberVoiceFile.to_bytes(voice, "Grumpy goblin")
var again := BlabberVoiceFile.from_bytes(bytes)
```

Loading checks every value: unknown settings are ignored, numbers are kept
inside each setting's range, and broken recordings are rejected. For web
exports, `BlabberWeb.place_file_input(button, true, Rect2(), "data")` reads
a picked file without decoding it as audio; take it with
`BlabberWeb.take_bytes()` once `BlabberWeb.state()` is `"done"` and
`BlabberWeb.file_kind()` is `"data"`.

## Inline tags

| Tag | Effect |
|-----|--------|
| `[pause=0.5]` | Silence, in seconds |
| `[speed=1.5]…[/speed]` | Faster or slower |
| `[pitch=1.2]…[/pitch]` | Higher or lower |
| `[volume=0.5]…[/volume]` | Louder or quieter |
| `[emote=angry]…[/emote]` | happy, excited, angry, sad, scared |
| `[whisper]…[/whisper]`, `[shout]…[/shout]` | Breathy and quiet, or loud and tense |
| `[shiver]…[/shiver]` | Trembling voice, shaking letters |
| `[wave]…[/wave]` | Sing-song pitch, letters ride a wave |
| `[swell]…[/swell]` | Grows louder and higher, letters swell |
| `[bounce]…[/bounce]` | Bright and bouncy, letters hop |
| `[droop]…[/droop]` | Sinks lower and slower, letters sag |
| `[jolt]…[/jolt]` | Rough, angry accents, letters jerk |
| `[reset]` | Back to normal |

Effects, an emotion and whisper or shout all stack: `[emote=sad][whisper]…`
is a sad whisper.

In a `RichTextLabel` with BBCode enabled, the text shows what the voice does:
the six effects move the letters, emotions get their matching effect (scared
shivers, happy bounces, sad droops, angry jolts), shouting is bold and bigger,
and whispers are small, faded italics. Turn this off with **Text Effects** on
the node. Other tags, like BBCode `[b]`, are left alone and stay silent. For a
plain `Label`, all tags are removed automatically.

To use the moving text in a label of your own:

```gdscript
BlabberTextEffects.install($Label)
$Label.text = BlabberParser.to_bbcode("[shiver]W-what was that?[/shiver]")
```

Punctuation shapes delivery: commas and full stops pause, `...` pauses longer,
`?` rises at the end, `!` adds energy, and words in CAPS are stressed.

## Signals and lip-sync

| Signal | Use |
|--------|-----|
| `started(text)` | A line began |
| `syllable_spoken(char_index)` | Bounce a portrait, play a particle |
| `word_spoken(word)` | Subtitles, word highlighting |
| `characters_revealed(count)` | Custom typewriter (matches `visible_characters`) |
| `mouth_moved(openness)` | Lip-sync, 0 = closed and 1 = wide open |
| `finished` | The line ended. Fires once for every line, also when it is skipped or cut off, so `await finished` never gets stuck |
| `interrupted` | The line was cut off by `stop()` or a new `speak()` (fires just before `finished`) |

`mouth_openness` is also available as a property. Methods: `speak()`, `stop()`,
`skip()` (reveal everything and finish), `is_speaking()`. Calling `speak()`
while a line is playing cuts that line off.

For positional audio, point **Player Path** at an `AudioStreamPlayer2D` or
`AudioStreamPlayer3D`. Use the **Bus** setting to add reverb or other effects.

## Baking

To pre-render lines (for mobile, or to cache common barks):

```gdscript
var wav := Blabbermouth.bake("Welcome!", preload("res://addons/blabbermouth/voices/woman.tres"))
$AudioStreamPlayer.stream = wav
wav.save_to_wav("user://welcome.wav")
```

## Lines and speech bubbles

A **line** is the words with their tags plus its own copy of the **speaker**:
a name, a voice and a bubble style. Save it as a `.blab` file and a game can
use all of it, or only the parts it wants.

```gdscript
var bubble := BlabberBubbleStyle.new()   # a StyleBoxFlat, plus font and text colors
bubble.bg_color = Color("f4ecdd")
bubble.border_color = Color("4a3423")
bubble.font = preload("res://fonts/Alegreya.ttf")
var aldric := BlabberSpeaker.create("Aldric", preload("res://addons/blabbermouth/voices/man.tres"), bubble)

var line := BlabberLine.create("Hello there, [wave]traveler![/wave]", aldric)  # copies the speaker
BlabberLineFile.write(line, "user://hello_traveler.blab")   # font included
```

With the plugin enabled, a `.blab` line in your project imports as a
`BlabberLine`. Show it with a **BlabberDialogue** node (a speech bubble with
the name tag on its top-left edge, the styled text and the voice):

```gdscript
$Dialogue.say(preload("res://lines/hello_traveler.blab"))
await $Dialogue.finished
```

Its **Use Voice**, **Use Text Style** and **Use Bubble Style** switches turn
parts off so you can bring your own. Or use the parts directly:

```gdscript
var line: BlabberLine = load("res://lines/hello_traveler.blab")
$Blabbermouth.speak(line.text, line.voice)                   # just the voice
$MyLabel.text = line.bbcode                                    # just the styled text
$MyPanel.add_theme_stylebox_override("panel", line.bubble)     # just the bubble
line.bubble.style_label($MyPanel/MyLabel)                      # and its font
```

`BlabberVoiceFile.read()` on a line file gives the speaker's voice, and
`BlabberLineFile.read(path, false)` skips an embedded font.

### Sound files

Bake a line once and use the sound anywhere, without Blabbermouth:

```gdscript
line.bake().save_to_wav("user://hello_traveler.wav")
var times := line.word_timings()   # [{word, start, end}, ...] in seconds, for captions
```

## How it works

1. **Parser** (`blabber_parser.gd`): reads the tags, splits the text into
   sentences and words, turns each word into sounds (phonetic or gibberish),
   then adds melody (pitch falls over a sentence and rises on questions), word
   stress, random wobble and timing.
2. **Synth** (`blabber_synth.gd`): a glottal pulse (the buzz), with jitter,
   shimmer and alternating-cycle rasp, plus breath noise, runs through four
   resonators that shape it into vowels. Two band-pass filters on noise make
   consonant hiss and bursts. Growl, ring modulation and a soft limiter come
   last. All settings glide between sounds, so speech flows instead of
   clicking.
3. **Sampler** (`blabber_sampler.gd`): the alternative to the synth when a
   voice has a recording. It uses the same timeline, signals and lip-sync.
   **Word player** (`blabber_word_player.gd`): mixes in the takes of
   vocabulary words, for both, where the parser left room for them.
4. **Node** (`blabbermouth.gd`): streams audio through an
   `AudioStreamGenerator` and fires signals at the moment each part is heard.

## Tools

Run headless from the project folder:

```sh
godot --headless --path . -s tools/test_render.gd -- /tmp/out   # render every preset, print timing
godot --headless --path . -s tools/test_node.gd                 # check the node's signals
godot --headless --path . -s tools/make_showcase.gd -- demo.wav # one clip of every voice
godot --headless --path . -s tools/make_presets.gd              # regenerate voices/*.tres
godot --headless --path . -s tools/test_samples.gd -- /tmp/out a.wav b.ogg  # import, slice and speak recordings
godot --headless --path . -s tools/test_voice_file.gd           # .blab files and the library (exits 1 on failure)
godot --headless --path . -s tools/test_signals.gd              # finished / interrupted (exits 1 on failure)
godot --headless --path . -s tools/test_g2p.gd                  # letters-to-sounds rules (exits 1 on failure)
godot --headless --path . -s tools/test_lines.gd                # effects, line files, dialogue bubble (exits 1 on failure)
godot --headless --path . -s tools/test_vocabulary.gd           # recorded words: matching, takes, effects, files (exits 1 on failure)
godot --headless --path . -s tools/test_editor.gd               # the demo editor: formatting, characters, vocabulary, export (exits 1 on failure)
godot --headless --path . -s tools/make_sample_line.gd          # regenerate demo/lines/hello_traveler.blab
```
