# Blabbermouth

A text-to-mumble voice engine for Godot 4.3+. It turns dialogue text into
character "speech" like Animal Crossing, Undertale or The Sims, from squeaky
critters to growling monsters, without any audio files.

Everything is generated in real time by a small formant synthesizer written in
GDScript. One voice costs about 3–6% of one CPU core. You can also record your
own voice (or any sound) and it will talk with that instead.

## Try it in your browser

The demo runs on the web, phones included: speak with the built-in voices,
or record your voice (or load a voice memo) and make it talk.

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

To build locally: install Godot 4.3 and its export templates, then run
`godot --headless --path . --export-release "Web" build/web/index.html`
and serve `build/web` with any static web server.

## Quick start

1. Copy `addons/blabbermouth` into your project.
2. Add a `Blabbermouth` node to a character.
3. In the inspector, set **Voice** to a preset from `addons/blabbermouth/voices/`
   (or make a new `BlabberVoice`), and optionally set **Label Path** to your
   dialogue `Label` / `RichTextLabel`.
4. Call it:

```gdscript
$Blabbermouth.speak("Hello there, traveler! [emote=happy]Lovely day, isn't it?")
await $Blabbermouth.finished
```

The label is revealed in sync with the voice (a typewriter effect), so you don't
need a separate timer.

To try it, open this repo as a Godot project and run it. The demo is a voice
designer with sliders, sample lines and a talking face.

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
articulation (hum ↔ crisp consonants), tenseness, breathiness, roughness
(rasp), growl, jitter, shimmer, vibrato, voicing (0 = whisper) and ring
modulation.

Make a voice in code:

```gdscript
var v := BlabberVoice.preset("goblin")
v.pitch = 300.0
v.growl = 0.4
$Blabbermouth.speak("Mine! All mine!", v)
```

Or tweak it in the demo and press **Save voice .tres**.

## Gibberish vs phonetic

- **Gibberish** (default): each word becomes made-up syllables built from the
  voice's `onsets`, `vowels` and `codas`. The same word always sounds the same,
  so players start to "learn" words. Change `language_seed` to give a species
  its own language. Turn on `speak_names` to keep capitalized names
  recognizable.
- **Phonetic**: follows the letters with simple English rules, so it sounds
  like mumbled speech that matches the text.

Any language works. Non-Latin text (Japanese, Russian and others) is spoken as
gibberish with a matching rhythm.

## Your own voice (samples)

Record yourself, a friend, your cat, or load any WAV, OGG or MP3, and the
engine speaks with those sounds instead of the synth.

In the demo, open the **My voice** tab:

1. Press **Record** and read the nonsense line out loud (or make any noises),
   or press **Load file…**, or drop a file on the window.
2. The recording is cleaned up (silence trimmed, room noise gated, volume
   evened out) and cut into syllables, shown as colored pieces. Cool
   colors are bright "ee" sounds and warm colors are dark "oo" sounds; grey
   pieces have no clear pitch.
3. Tap a piece to hear it. Turn on **Tap removes** to drop coughs and clicks.
4. Pick a **Character** (as recorded, tiny critter, kid, giant…), then Speak.
   **Save voice** writes a `.res` with the recording inside.

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

## Inline tags

| Tag | Effect |
|-----|--------|
| `[pause=0.5]` | Silence, in seconds |
| `[speed=1.5]…[/speed]` | Faster or slower |
| `[pitch=1.2]…[/pitch]` | Higher or lower |
| `[volume=0.5]…[/volume]` | Louder or quieter |
| `[emote=angry]…[/emote]` | happy, excited, angry, sad, scared, whisper, shout |
| `[whisper]…[/whisper]`, `[shout]…[/shout]` | Shortcuts |
| `[reset]` | Back to normal |

Other tags, like BBCode `[b]`, are left alone and stay silent, so the same
string can go straight into a `RichTextLabel` with BBCode enabled.
For a plain `Label`, all tags are removed automatically.

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
| `finished` | The line ended or was skipped |

`mouth_openness` is also available as a property. Methods: `speak()`, `stop()`,
`skip()` (reveal everything and finish), `is_speaking()`.

For positional audio, point **Player Path** at an `AudioStreamPlayer2D` or
`AudioStreamPlayer3D`. Use the **Bus** setting to add reverb or other effects.

## Baking

To pre-render lines (for mobile, or to cache common barks):

```gdscript
var wav := Blabbermouth.bake("Welcome!", preload("res://addons/blabbermouth/voices/woman.tres"))
$AudioStreamPlayer.stream = wav
wav.save_to_wav("user://welcome.wav")
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
```
