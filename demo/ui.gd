extends RefCounted
## The demo's look: colors, fonts, the theme, icons and a few small widgets.

const BG := Color("121318")
const CARD := Color("181a21")
const PANEL := Color("1c1e25")
const RAISED := Color("22252d")
const BUTTON := Color("262932")
const LINE := Color("353946")
const LINE_SOFT := Color("2f333d")
const TEXT := Color("f3f1ec")
const TEXT_2 := Color("c9ccd3")
const DIM := Color("a0a4ae")
const FAINT := Color("8e929c")
const ACCENT := Color("ffd166")
const ACCENT_INK := Color("1a1405")
const ON := Color("f3f1ec")
const ON_INK := Color("121318")
const REC := Color("ff6b5e")
const CLEAR := Color(0, 0, 0, 0)

const FONT := preload("res://demo/fonts/dm_sans.ttf")
const FONT_BOLD := preload("res://demo/fonts/dm_sans_semibold.ttf")
const FONT_MONO := preload("res://demo/fonts/jetbrains_mono.ttf")

## 24×24 line icons. Drawn white; buttons tint them.
const ICONS := {
	"logo": "<path d='M5 5h14a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-8l-5 4v-4H5a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3z'/><path d='M7 12c1.5-2.2 3 2.2 4.5 0s3 2.2 4.5 0' stroke-width='2'/>",
	"play": "<path d='M7 4.5v15a1 1 0 0 0 1.5.86l12-7.5a1 1 0 0 0 0-1.72l-12-7.5A1 1 0 0 0 7 4.5z' fill='white' stroke='none'/>",
	"stop": "<rect x='6' y='6' width='12' height='12' rx='2' fill='white' stroke='none'/>",
	"synth": "<path d='M3 12h2l2-6 3 12 3-9 2 5 2-2h4'/>",
	"mic": "<rect x='9' y='3' width='6' height='12' rx='3'/><path d='M5 11a7 7 0 0 0 14 0'/><path d='M12 18v3'/>",
	"down": "<path d='M6 9l6 6 6-6'/>",
	"up": "<path d='M6 15l6-6 6 6'/>",
	"right": "<path d='M9 6l6 6-6 6'/>",
	"export": "<path d='M12 3v12'/><path d='M7 10l5 5 5-5'/><path d='M5 21h14'/>",
	"open": "<path d='M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'/>",
	"plus": "<path d='M12 5v14M5 12h14'/>",
	"copy": "<rect x='9' y='9' width='11' height='11' rx='2'/><path d='M5 15V6a2 2 0 0 1 2-2h8'/>",
	"trash": "<path d='M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3'/>",
	"shuffle": "<path d='M4 7h3c5 0 5 10 10 10h3M4 17h3c2 0 3-1.5 4-3.3M13 9.3C14 7.5 15 7 17 7h3M17 4l3 3-3 3M17 14l3 3-3 3'/>",
	"x": "<path d='M6 6l12 12M18 6L6 18'/>",
	"rec": "<circle cx='12' cy='12' r='6' fill='white' stroke='none'/>",
}

static var _icons := {}


## An icon texture, drawn at 2× so it stays sharp on dense screens.
static func icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'>%s</svg>" % ICONS[name]
	var img := Image.new()
	img.load_svg_from_string(svg, 2.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[name] = tex
	return tex


static func box(color: Color, radius := 12, border := CLEAR, border_w := 0, pad_x := 12.0, pad_y := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)

	var focus := box(CLEAR, 13, ACCENT, 2)
	focus.draw_center = false
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for type in ["Button", "OptionButton", "ColorPickerButton", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(CLEAR, 12, LINE, 1, 14, 10))
		t.set_stylebox("hover", type, box(RAISED, 12, LINE, 1, 14, 10))
		t.set_stylebox("pressed", type, box(ON, 12, ON, 1, 14, 10))
		t.set_stylebox("hover_pressed", type, box(Color("ffffff"), 12, ON, 1, 14, 10))
		t.set_stylebox("disabled", type, box(CLEAR, 12, LINE_SOFT, 1, 14, 10))
		t.set_stylebox("focus", type, focus)
		t.set_font("font", type, FONT_BOLD)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, TEXT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_pressed_color", type, ON_INK)
		t.set_color("font_hover_pressed_color", type, ON_INK)
		t.set_color("font_disabled_color", type, FAINT)
		t.set_color("icon_normal_color", type, TEXT)
		t.set_color("icon_hover_color", type, TEXT)
		t.set_color("icon_focus_color", type, TEXT)
		t.set_color("icon_pressed_color", type, ON_INK)
		t.set_color("icon_hover_pressed_color", type, ON_INK)
		t.set_color("icon_disabled_color", type, FAINT)
		t.set_constant("h_separation", type, 8)
		t.set_constant("icon_max_width", type, 20)
	# CheckButton: just the switch and its text, no box.
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckButton", box(CLEAR, 12, CLEAR, 0, 2, 8))
	t.set_font("font", "CheckButton", FONT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)

	# Main action: yellow.
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary", box(ACCENT, 16, CLEAR, 0, 26, 14))
	t.set_stylebox("hover", "Primary", box(Color("ffdc85"), 16, CLEAR, 0, 26, 14))
	t.set_stylebox("pressed", "Primary", box(Color("f0c050"), 16, CLEAR, 0, 26, 14))
	t.set_stylebox("hover_pressed", "Primary", box(Color("f0c050"), 16, CLEAR, 0, 26, 14))
	t.set_stylebox("disabled", "Primary", box(Color(ACCENT, 0.25), 16, CLEAR, 0, 26, 14))
	t.set_color("font_disabled_color", "Primary", Color(ACCENT_INK, 0.6))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color",
			"icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(c, "Primary", ACCENT_INK)
	t.set_font_size("font_size", "Primary", 18)
	# Filled grey button (Export).
	t.set_type_variation("Raised", "Button")
	t.set_stylebox("normal", "Raised", box(BUTTON, 12, LINE, 1, 16, 10))
	t.set_stylebox("hover", "Raised", box(Color("30343e"), 12, LINE, 1, 16, 10))
	# Header tabs: underlined when on.
	t.set_type_variation("Tab", "Button")
	var tab := box(CLEAR, 0, CLEAR, 0, 16, 10)
	var tab_on := box(CLEAR, 0, CLEAR, 0, 16, 10)
	tab_on.border_color = ACCENT
	tab_on.border_width_bottom = 2
	t.set_stylebox("normal", "Tab", tab)
	t.set_stylebox("hover", "Tab", tab)
	t.set_stylebox("pressed", "Tab", tab_on)
	t.set_stylebox("hover_pressed", "Tab", tab_on)
	t.set_color("font_color", "Tab", DIM)
	t.set_color("font_hover_color", "Tab", TEXT)
	t.set_color("font_pressed_color", "Tab", TEXT)
	t.set_color("font_hover_pressed_color", "Tab", TEXT)
	# Segmented controls: no outline, light when on.
	t.set_type_variation("Segment", "Button")
	t.set_stylebox("normal", "Segment", box(CLEAR, 10, CLEAR, 0, 14, 10))
	t.set_stylebox("hover", "Segment", box(RAISED, 10, CLEAR, 0, 14, 10))
	t.set_stylebox("pressed", "Segment", box(ON, 10, CLEAR, 0, 14, 10))
	t.set_stylebox("hover_pressed", "Segment", box(ON, 10, CLEAR, 0, 14, 10))
	t.set_color("font_color", "Segment", DIM)
	t.set_color("icon_normal_color", "Segment", DIM)
	# Text-only link.
	t.set_type_variation("Link", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "Link", box(CLEAR, 8, CLEAR, 0, 4, 8))
	t.set_color("font_color", "Link", ACCENT)
	t.set_color("font_hover_color", "Link", Color("ffe29a"))
	t.set_color("font_pressed_color", "Link", ACCENT)
	t.set_color("font_hover_pressed_color", "Link", ACCENT)
	t.set_color("icon_normal_color", "Link", ACCENT)
	t.set_color("icon_hover_color", "Link", Color("ffe29a"))

	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, box(BG, 12, LINE, 1, 14, 10))
		t.set_stylebox("focus", type, box(BG, 12, ACCENT, 1, 14, 10))
		t.set_stylebox("read_only", type, box(BG, 12, LINE_SOFT, 1, 14, 10))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_placeholder_color", type, FAINT)
		t.set_color("caret_color", type, ACCENT)
		t.set_color("selection_color", type, Color(ACCENT, 0.32))
		t.set_color("font_selected_color", type, TEXT)
	t.set_font_size("font_size", "TextEdit", 17)
	t.set_constant("line_spacing", "TextEdit", 6)

	var popup := box(PANEL, 14, LINE, 1, 6, 6)
	popup.shadow_color = Color(0, 0, 0, 0.45)
	popup.shadow_size = 18
	popup.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(RAISED, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", box(PANEL, 16, LINE, 1, 20, 16))
	t.set_stylebox("embedded_border", "Window", box(PANEL, 16, LINE, 1, 0, 0))
	t.set_stylebox("embedded_unfocused_border", "Window", box(PANEL, 16, LINE, 1, 0, 0))
	t.set_color("title_color", "Window", TEXT)
	t.set_font("title_font", "Window", FONT_BOLD)
	t.set_stylebox("panel", "TooltipPanel", box(RAISED, 8, LINE, 1, 10, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	var track := box(LINE_SOFT, 3, CLEAR, 0, 0, 2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 3, CLEAR, 0, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color("ffdc85"), 3, CLEAR, 0, 0, 2))
	t.set_icon("grabber", "HSlider", _dot(ON, 9))
	t.set_icon("grabber_highlight", "HSlider", _dot(Color.WHITE, 10))
	t.set_icon("grabber_disabled", "HSlider", _dot(FAINT, 9))

	var bar := box(CLEAR, 4, CLEAR, 0, 3, 3)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, bar)
		t.set_stylebox("scroll_focus", type, bar)
		t.set_stylebox("grabber", type, box(LINE, 4, CLEAR, 0, 3, 3))
		t.set_stylebox("grabber_highlight", type, box(Color("4a4f5c"), 4, CLEAR, 0, 3, 3))
		t.set_stylebox("grabber_pressed", type, box(Color("4a4f5c"), 4, CLEAR, 0, 3, 3))

	t.set_stylebox("panel", "PanelContainer", box(PANEL, 24, CLEAR, 0, 20, 20))
	t.set_stylebox("separator", "HSeparator", box(LINE_SOFT, 0, CLEAR, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 1)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT, 0.35))
	t.set_stylebox("background", "ProgressBar", box(LINE_SOFT, 3, CLEAR, 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(REC, 3, CLEAR, 0, 0, 0))
	t.set_stylebox("panel", "ItemList", box(BG, 12, LINE, 1, 6, 6))
	t.set_stylebox("selected", "ItemList", box(RAISED, 8, ACCENT, 1))
	t.set_stylebox("selected_focus", "ItemList", box(RAISED, 8, ACCENT, 1))
	t.set_stylebox("hovered", "ItemList", box(RAISED, 8))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 10)
	return t


static func _dot(color: Color, radius: int) -> Texture2D:
	var d := radius * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) / 2.0
	for y in d:
		for x in d:
			var a := clampf(radius + 0.5 - Vector2(x + 0.5, y + 0.5).distance_to(c), 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 15, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", FONT_BOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Small caps heading, like "VOICE SOURCE".
static func eyebrow(text: String) -> Label:
	var l := label(text.to_upper(), 12, DIM, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func heading(text: String, size := 17) -> Label:
	var l := label(text, size, TEXT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func button(text: String, cb: Callable, icon_name := "", variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = icon(icon_name)
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	return b


static func panel(color: Color, radius: int, pad_x := 20.0, pad_y := 20.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, CLEAR, 0, pad_x, pad_y))
	return p


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Buttons in a dark tray where one is on at a time. Returns [tray, buttons].
static func segmented(labels: Array, icons: Array = []) -> Array:
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", box(BG, 14, CLEAR, 0, 4, 4))
	var row := hbox(4)
	tray.add_child(row)
	var group := ButtonGroup.new()
	var buttons: Array = []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "Segment"
		b.custom_minimum_size.y = 40
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < icons.size() and icons[i] != "":
			b.icon = icon(icons[i])
		row.add_child(b)
		buttons.append(b)
	return [tray, buttons]
