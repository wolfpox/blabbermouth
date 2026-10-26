@tool
class_name BlabberBubbleStyle
extends StyleBoxFlat
## A speaker's speech bubble. It is a StyleBoxFlat (fill, outline, corners,
## shadow, padding), so it works as the style of any panel, plus the font,
## the text colors and the name tag colors.
## [codeblock]
## $Panel.add_theme_stylebox_override("panel", line.bubble)
## line.bubble.style_label($Panel/Text)
## [/codeblock]

const MAX_FONT_BYTES := 8 * 1024 * 1024

@export_group("Text")
## Leave empty for the theme's font.
@export var font: Font
@export_range(8, 128, 1, "suffix:px") var font_size := 24
@export var text_color := Color("2a1d12")
## For whispered words.
@export var muted_color := Color("6b5a47")

@export_group("Name tag")
@export var name_color := Color("4a3423")
@export var name_text_color := Color("f4ecdd")

@export_group("Tail")
## A small pointer at the bottom left, toward the speaker.
@export var tail := true
@export_range(0, 64, 1, "suffix:px") var tail_size := 16


func _init() -> void:
	bg_color = Color("f4ecdd")
	border_color = Color("4a3423")
	set_border_width_all(3)
	set_corner_radius_all(16)
	content_margin_left = 28.0
	content_margin_right = 28.0
	content_margin_top = 26.0
	content_margin_bottom = 22.0


## Sets a Label's or RichTextLabel's font, size and color to match the bubble.
## Bold and italic come from the same font.
func style_label(label: Control) -> void:
	if label is RichTextLabel:
		if font:
			label.add_theme_font_override("normal_font", font)
			label.add_theme_font_override("bold_font", _variant(0.9, 0.0))
			label.add_theme_font_override("italics_font", _variant(0.0, 0.2))
			label.add_theme_font_override("bold_italics_font", _variant(0.9, 0.2))
		for slot in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			label.add_theme_font_size_override(slot, font_size)
		label.add_theme_color_override("default_color", text_color)
	elif label is Label:
		if font:
			label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", text_color)


## The name tag's box: name_color with the bubble's outline.
func name_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = name_color
	s.border_color = border_color
	s.set_border_width_all(2)
	s.set_corner_radius_all(mini(corner_radius_top_left, 10))
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


## Plain values for saving in a line file. With embed_font, a font file's
## contents go in too, so the bubble looks the same on any machine.
func to_dict(embed_font := true) -> Dictionary:
	var d := {
		"fill": bg_color.to_html(), "outline": border_color.to_html(),
		"outline_width": border_width_top, "corner_radius": corner_radius_top_left,
		"shadow_color": shadow_color.to_html(), "shadow_size": shadow_size,
		"shadow_offset": [shadow_offset.x, shadow_offset.y],
		"padding": [content_margin_left, content_margin_top, content_margin_right, content_margin_bottom],
		"font_size": font_size, "text_color": text_color.to_html(), "muted_color": muted_color.to_html(),
		"name_color": name_color.to_html(), "name_text_color": name_text_color.to_html(),
		"tail": tail, "tail_size": tail_size,
	}
	if font:
		var f := {"name": font.get_font_name()}
		var base: Font = font
		while base is FontVariation and base.base_font:
			base = base.base_font
		if embed_font and base is FontFile and base.data.size() > 0 and base.data.size() <= MAX_FONT_BYTES:
			f["data"] = Marshalls.raw_to_base64(base.data)
		elif base is SystemFont:
			f["system"] = Array(base.font_names)
		d["font"] = f
	return d


## Rebuilds a bubble from to_dict() values. Anything missing or wrong keeps
## its default. load_font false skips embedded font data.
static func from_dict(d: Dictionary, load_font := true) -> BlabberBubbleStyle:
	var b := BlabberBubbleStyle.new()
	b.bg_color = _color(d, "fill", b.bg_color)
	b.border_color = _color(d, "outline", b.border_color)
	b.set_border_width_all(_int(d, "outline_width", 3, 0, 32))
	b.set_corner_radius_all(_int(d, "corner_radius", 16, 0, 200))
	b.shadow_color = _color(d, "shadow_color", b.shadow_color)
	b.shadow_size = _int(d, "shadow_size", 0, 0, 100)
	var so = d.get("shadow_offset")
	if typeof(so) == TYPE_ARRAY and so.size() == 2 and _num(so[0]) and _num(so[1]):
		b.shadow_offset = Vector2(clampf(so[0], -100.0, 100.0), clampf(so[1], -100.0, 100.0))
	var pad = d.get("padding")
	if typeof(pad) == TYPE_ARRAY and pad.size() == 4:
		var ok := true
		for v in pad:
			ok = ok and _num(v)
		if ok:
			b.content_margin_left = clampf(pad[0], 0.0, 200.0)
			b.content_margin_top = clampf(pad[1], 0.0, 200.0)
			b.content_margin_right = clampf(pad[2], 0.0, 200.0)
			b.content_margin_bottom = clampf(pad[3], 0.0, 200.0)
	b.font_size = _int(d, "font_size", 24, 8, 128)
	b.text_color = _color(d, "text_color", b.text_color)
	b.muted_color = _color(d, "muted_color", b.muted_color)
	b.name_color = _color(d, "name_color", b.name_color)
	b.name_text_color = _color(d, "name_text_color", b.name_text_color)
	if typeof(d.get("tail")) == TYPE_BOOL:
		b.tail = d.tail
	b.tail_size = _int(d, "tail_size", 16, 0, 64)
	var f = d.get("font")
	if typeof(f) == TYPE_DICTIONARY:
		if load_font and typeof(f.get("data")) == TYPE_STRING and f.data.length() <= MAX_FONT_BYTES * 4 / 3 + 4:
			var bytes := Marshalls.base64_to_raw(f.data)
			if bytes.size() > 0:
				var ff := FontFile.new()
				ff.data = bytes
				b.font = ff
		elif typeof(f.get("system")) == TYPE_ARRAY:
			var names := PackedStringArray()
			for n in f.system:
				if typeof(n) == TYPE_STRING and names.size() < 8:
					names.append((n as String).left(100))
			if not names.is_empty():
				var sf := SystemFont.new()
				sf.font_names = names
				b.font = sf
	return b


func _variant(embolden: float, slant: float) -> Font:
	var v := FontVariation.new()
	v.base_font = font
	v.variation_embolden = embolden
	if slant != 0.0:
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(slant, 1), Vector2.ZERO)
	return v


static func _num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _int(d: Dictionary, key: String, fallback: int, lo: int, hi: int) -> int:
	var v = d.get(key)
	return clampi(int(v), lo, hi) if _num(v) else fallback


static func _color(d: Dictionary, key: String, fallback: Color) -> Color:
	var v = d.get(key)
	if typeof(v) == TYPE_STRING and Color.html_is_valid(v):
		return Color.html(v)
	return fallback
