@tool
class_name BlabberTextEffects
extends RefCounted
## Moving-text effects for RichTextLabel that match the voice effects:
## [shiver], [swell], [bounce], [droop] and [jolt]. ([wave] is built into Godot.)
##
## The Blabbermouth node installs these on its label for you. To use them on
## a label of your own:
## [codeblock]
## BlabberTextEffects.install($Label)
## $Label.text = BlabberParser.to_bbcode("[shiver]W-what was that?[/shiver]")
## [/codeblock]
## Each tag takes an optional strength, e.g. [code][shiver level=2][/code].


## Adds the effects to a label, skipping any it already has.
static func install(label: RichTextLabel) -> void:
	var effects: Array = label.custom_effects.duplicate()
	var have := {}
	for e in effects:
		if e is RichTextEffect and "bbcode" in e:
			have[e.bbcode] = true
	for e in create_all():
		if not have.has(e.bbcode):
			effects.append(e)
	label.custom_effects = effects


## One new instance of every effect.
static func create_all() -> Array[RichTextEffect]:
	return [Shiver.new(), Swell.new(), Bounce.new(), Droop.new(), Jolt.new()]


static func _noise(a: int, b: int) -> float:
	return float(hash(Vector2i(a, b)) & 0xffff) / 65535.0 - 0.5


static func _level(fx: CharFXTransform) -> float:
	return float(fx.env.get("level", 1.0))


## Small, fast, random trembling.
class Shiver:
	extends RichTextEffect
	var bbcode := "shiver"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var step := int(fx.elapsed_time * 22.0)
		var k := BlabberTextEffects._level(fx) * 2.2
		fx.offset += Vector2(BlabberTextEffects._noise(fx.relative_index, step),
			BlabberTextEffects._noise(step, fx.relative_index + 7)) * k
		return true


## Letters grow and shrink in a slow ripple.
class Swell:
	extends RichTextEffect
	var bbcode := "swell"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var w := 0.5 + 0.5 * sin(fx.elapsed_time * 2.8 - fx.relative_index * 0.35)
		var s := 1.0 + 0.2 * BlabberTextEffects._level(fx) * w
		fx.transform = fx.transform * Transform2D().scaled(Vector2(s, s))
		return true


## Letters hop up one after another.
class Bounce:
	extends RichTextEffect
	var bbcode := "bounce"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var h := absf(sin(fx.elapsed_time * 7.0 - fx.relative_index * 0.5))
		fx.offset.y -= h * 5.0 * BlabberTextEffects._level(fx)
		return true


## Letters sink and tilt as the phrase goes on.
class Droop:
	extends RichTextEffect
	var bbcode := "droop"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var k := BlabberTextEffects._level(fx)
		fx.offset.y += minf(fx.relative_index * 0.6, 9.0) * k
		var tilt := (0.025 if fx.relative_index % 2 == 0 else -0.025) * k
		fx.transform = fx.transform * Transform2D(tilt, Vector2.ZERO)
		fx.color.a *= 0.85
		return true


## Sharp, angry jerks every so often.
class Jolt:
	extends RichTextEffect
	var bbcode := "jolt"

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var step := int(fx.elapsed_time * 9.0)
		if posmod(hash(Vector2i(step, fx.relative_index)), 3) == 0:
			var k := BlabberTextEffects._level(fx)
			fx.offset += Vector2(BlabberTextEffects._noise(step, fx.relative_index) * 3.0,
				BlabberTextEffects._noise(fx.relative_index, step) * 3.0) * k
			fx.transform = fx.transform * Transform2D(BlabberTextEffects._noise(step + 3, fx.relative_index) * 0.12 * k, Vector2.ZERO)
		return true
