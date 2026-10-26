@tool
@icon("res://addons/blabbermouth/icon.svg")
class_name BlabberDialogue
extends MarginContainer
## A speech bubble that says a BlabberLine: the speaker's bubble with a name
## tag on its top-left edge, the text revealed with its effects, and the voice.
## Turn off any part to use your own instead.
## [codeblock]
## $Dialogue.say(preload("res://lines/hello_traveler.blab"))
## await $Dialogue.finished
## [/codeblock]
## Give the node a width (in a container, or with custom_minimum_size);
## its height follows the text.

## Emitted when a line ends, however it ends (see Blabbermouth.finished).
signal finished

## The line to show. Setting it in the editor previews the bubble.
@export var line: BlabberLine:
	set(v):
		line = v
		if is_node_ready():
			_show(line, false)
## Speak with the speaker's voice. Off: use voice below, or stay silent if it's empty.
@export var use_voice := true
## Show effects as moving text, shouting bold and whispers small.
@export var use_text_style := true
## Use the speaker's bubble, font and colors. Off: your theme's panel and font.
@export var use_bubble_style := true
## The voice to use when use_voice is off. Leave empty for a silent line
## that still types out at the speaker's pace.
@export var voice: BlabberVoice
## Say line as soon as the node is ready.
@export var autoplay := false

var blabbermouth: Blabbermouth
var panel: PanelContainer
var text_label: RichTextLabel
var name_tag: PanelContainer
var name_label: Label

var _overlay: _Overlay


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	add_child(panel, false, Node.INTERNAL_MODE_FRONT)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Lay out the whole line first, so the bubble doesn't grow while it types.
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text_label)
	_overlay = _Overlay.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay, false, Node.INTERNAL_MODE_FRONT)
	name_tag = PanelContainer.new()
	name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(name_tag)
	name_label = Label.new()
	name_tag.add_child(name_label)
	if not Engine.is_editor_hint():
		blabbermouth = Blabbermouth.new()
		blabbermouth.label = text_label
		add_child(blabbermouth, false, Node.INTERNAL_MODE_FRONT)
		blabbermouth.finished.connect(finished.emit)
	_show(line, false)
	if autoplay and line and not Engine.is_editor_hint():
		say(line)


## Shows and speaks a line (or the current one). Cuts off a line already playing.
func say(p_line: BlabberLine = null) -> void:
	if p_line:
		line = p_line
	_show(line, true)


## Reveals the whole line at once and ends it.
func skip() -> void:
	if blabbermouth:
		blabbermouth.skip()


## Stops speaking without revealing the rest.
func stop() -> void:
	if blabbermouth:
		blabbermouth.stop()


func is_speaking() -> bool:
	return blabbermouth != null and blabbermouth.is_speaking()


func _show(p_line: BlabberLine, speak: bool) -> void:
	if panel == null:
		return
	var style: BlabberBubbleStyle = p_line.bubble if p_line and use_bubble_style else null
	_apply_style(style)
	var who := p_line.speaker_name if p_line else ""
	name_label.text = who
	name_tag.visible = who != ""
	var tag_h := name_tag.get_combined_minimum_size().y if name_tag.visible else 0.0
	add_theme_constant_override("margin_top", ceili(tag_h * 0.5))
	add_theme_constant_override("margin_left", 0)
	add_theme_constant_override("margin_right", 0)
	add_theme_constant_override("margin_bottom", style.tail_size if style and style.tail else 0)
	name_tag.position = Vector2(20.0, -tag_h * 0.5)
	_overlay.style = style
	_overlay.queue_redraw()
	if p_line == null:
		text_label.text = ""
		return
	if not speak or blabbermouth == null:
		# Preview: the whole line, styled, no sound.
		if use_text_style:
			BlabberTextEffects.install(text_label)
			text_label.text = BlabberParser.to_bbcode(p_line.text, text_label.get_theme_font_size("normal_font_size"),
				style.muted_color if style else Color(0, 0, 0, 0))
		else:
			text_label.text = BlabberParser.strip_tags(p_line.text)
		text_label.visible_characters = -1
		return
	var v := p_line.voice if use_voice and p_line.voice else voice
	if v == null:
		# Silent, but typed out at the speaker's pace.
		v = BlabberVoiceFile.copy_voice(p_line.voice) if p_line.voice else BlabberVoice.preset("man")
		v.volume = 0.0
	blabbermouth.text_effects = use_text_style
	blabbermouth.whisper_color = style.muted_color if style else Color(0, 0, 0, 0)
	blabbermouth.speak(p_line.text, v)


func _apply_style(style: BlabberBubbleStyle) -> void:
	for slot in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
		text_label.remove_theme_font_override(slot)
	for slot in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		text_label.remove_theme_font_size_override(slot)
	text_label.remove_theme_color_override("default_color")
	name_label.remove_theme_font_override("font")
	name_label.remove_theme_font_size_override("font_size")
	name_label.remove_theme_color_override("font_color")
	if style == null:
		panel.remove_theme_stylebox_override("panel")
		name_tag.remove_theme_stylebox_override("panel")
		return
	panel.add_theme_stylebox_override("panel", style)
	style.style_label(text_label)
	name_tag.add_theme_stylebox_override("panel", style.name_style())
	if style.font:
		name_label.add_theme_font_override("font", style.font)
	name_label.add_theme_font_size_override("font_size", roundi(style.font_size * 0.75))
	name_label.add_theme_color_override("font_color", style.name_text_color)


## Draws the tail under the bubble, and holds the name tag.
class _Overlay:
	extends Control
	var style: BlabberBubbleStyle

	func _draw() -> void:
		if style == null or not style.tail or style.tail_size <= 0:
			return
		var h := size.y
		var t := float(style.tail_size)
		var bw := float(style.border_width_bottom)
		var x := maxf(float(style.corner_radius_bottom_left), 24.0) + 8.0
		# Fill reaches up over the bubble's bottom outline so the tail joins it.
		var fill := PackedVector2Array([Vector2(x, h - bw - 1.0), Vector2(x + t * 1.5, h - bw - 1.0), Vector2(x - t * 0.25, h + t)])
		draw_colored_polygon(fill, style.bg_color)
		if bw > 0.0:
			var edge := PackedVector2Array([Vector2(x, h - bw * 0.5), Vector2(x - t * 0.25, h + t), Vector2(x + t * 1.5, h - bw * 0.5)])
			draw_polyline(edge, style.border_color, bw, true)
