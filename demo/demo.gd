extends Control
## Blabbermouth's editor: write a line, style the words in the speaker's
## bubble, hear it, and export it for a game (or as a sound file).

const Ui := preload("res://demo/ui.gd")
const Clickable := preload("res://demo/clickable.gd")
const Sheet := preload("res://demo/sheet.gd")
const Cast := preload("res://demo/cast.gd")
const LinePage := preload("res://demo/line_page.gd")
const CastPage := preload("res://demo/cast_page.gd")
const VocabularyPage := preload("res://demo/vocabulary_page.gd")
const LibraryPanel := preload("res://demo/library_panel.gd")
const SampleStudio := preload("res://demo/sample_studio.gd")

## Where the editor keeps its characters and line. Tests point it elsewhere.
var save_path := Cast.SAVE_PATH
## Lay out as if the window were this size (for tests, where it can't change).
var test_size := Vector2i.ZERO
var members: Array = []
var current := 0
## Sets of recorded words (vocabularies). Each character uses some of them.
var sets: Array = []

var margin: MarginContainer
var header: BoxContainer
var nav: HBoxContainer
var tabs := {}
var open_button: Button
var export_button: Button
var scroll: ScrollContainer
var pages: VBoxContainer
var line_page: LinePage
var cast_page: CastPage
var vocabulary_page: VocabularyPage
var voices_page: VBoxContainer
var library: LibraryPanel
var status: Label
var menu: Control
var record_sheet: Sheet
var studio: SampleStudio
var use_recording_button: Button
var record_hint: Label
var export_sheet: Sheet
var export_font_check: CheckButton
var export_status: Label
var export_note: Label
var confirm: ConfirmationDialog
var _sample_i := -1
## Sets changed since they were last saved.
var _dirty_sets := {}
## The sets came from an older version's one vocabulary file, removed once they're saved.
var _migrated := false
var _save_timer: Timer
var _dialog: FileDialog
var _status_timer: Timer


func _ready() -> void:
	theme = Ui.make_theme()
	var bg := ColorRect.new()
	bg.color = Ui.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var col := Ui.vbox(20)
	margin.add_child(col)
	col.add_child(_header())
	status = Ui.label("", 14, Ui.ACCENT)
	status.visible = false
	col.add_child(status)
	pages = Ui.vbox(0)
	col.add_child(pages)

	line_page = LinePage.new()
	pages.add_child(line_page)
	line_page.edited.connect(save_soon)
	line_page.pick_speaker.connect(_open_menu)
	line_page.record_pressed.connect(_open_recorder)
	line_page.more_pressed.connect(func() -> void: show_page("cast"))
	line_page.speaker_changed.connect(func(_what: String) -> void: save_soon())
	line_page.sample_pressed.connect(_next_sample)

	cast_page = CastPage.new()
	pages.add_child(cast_page)
	cast_page.picked.connect(set_current)
	cast_page.add_pressed.connect(_add_member)
	cast_page.duplicate_pressed.connect(_duplicate_member)
	cast_page.delete_pressed.connect(_delete_member)
	cast_page.record_pressed.connect(_open_recorder)
	cast_page.speaker_changed.connect(func(_what: String) -> void:
		line_page.refresh_speaker()
		save_soon())

	vocabulary_page = VocabularyPage.new()
	vocabulary_page.get_member = member
	vocabulary_page.get_members = func() -> Array: return members
	pages.add_child(vocabulary_page)
	vocabulary_page.changed.connect(func(vs: BlabberVocabulary) -> void:
		if vs:
			_dirty_sets[vs] = true
		line_page.refresh_speaker()
		save_soon())
	vocabulary_page.deleted.connect(func(vs: BlabberVocabulary) -> void:
		_dirty_sets.erase(vs)
		Cast.delete_set_file(vs, save_path)
		Cast.forget_id(vs)
		line_page.refresh_speaker()
		save_soon())
	vocabulary_page.export_pressed.connect(_export_set)
	line_page.aside.get_sets = func() -> Array: return sets
	cast_page.editor.get_sets = func() -> Array: return sets

	voices_page = Ui.vbox(16)
	pages.add_child(voices_page)
	voices_page.add_child(Ui.heading("Voices", 26))
	voices_page.add_child(Ui.label("Save a character's voice on this device, or move voices between devices as .blab voice files. Opening a voice gives it to the current character.", 14, Ui.DIM))
	var lib_panel := Ui.panel(Ui.PANEL, 28, 24, 24)
	voices_page.add_child(lib_panel)
	library = LibraryPanel.new()
	library.handle_files = false
	library.get_voice = func() -> BlabberVoice: return BlabberVoiceFile.copy_voice(member().speaker.voice)
	library.resolve_sets = _resolve_links
	library.get_name_hint = func() -> String: return member().speaker.display_name
	library.opened.connect(_open_voice)
	lib_panel.add_child(library)

	_build_menu()
	_build_recorder()
	_build_export()
	confirm = ConfirmationDialog.new()
	add_child(confirm)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.8
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.wait_time = 6.0
	_status_timer.timeout.connect(func() -> void: status.visible = false)
	add_child(_status_timer)

	var st := Cast.load_state(save_path)
	sets = st.sets
	_migrated = st.migrated
	if _migrated:
		for vs in sets:
			_dirty_sets[vs] = true
	if not st.has("members"):
		members = Cast.defaults()
		current = 0
		for m in members:
			for vs in sets:
				m.set_uses(vs, true)
		line_page.set_member(members[0])
		line_page.load_source(Cast.SAMPLES[0][1])
		_sample_i = 0
	else:
		members = st.members
		current = st.current
		line_page.set_member(members[current])
		line_page.load_source(st.line)
	if _migrated:
		save_soon()
	show_page("line")
	get_window().size_changed.connect(_layout)
	get_window().files_dropped.connect(_on_files_dropped)
	_layout.call_deferred()
	set_process(BlabberWeb.available())


func member() -> Cast.Member:
	return members[current]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _save_timer and not _save_timer.is_stopped():
		save_now()


# --- Layout --------------------------------------------------------------------

func _header() -> Control:
	header = BoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var top := Ui.hbox(28)
	var brand := Ui.hbox(10)
	var logo := TextureRect.new()
	logo.texture = Ui.icon("logo")
	logo.modulate = Ui.ACCENT
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(30, 30)
	brand.add_child(logo)
	var name_l := Ui.heading("Blabbermouth", 21)
	name_l.name = "Title"
	brand.add_child(name_l)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(brand)
	nav = Ui.hbox(4)
	var group := ButtonGroup.new()
	for t in [["line", "Line"], ["cast", "Characters"], ["vocabulary", "Vocabulary"], ["voices", "Voices"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "Tab"
		b.custom_minimum_size.y = 46
		b.pressed.connect(show_page.bind(t[0]))
		nav.add_child(b)
		tabs[t[0]] = b
	top.add_child(nav)
	header.add_child(top)
	var actions := Ui.hbox(8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_END
	open_button = Ui.button("Open", _open_pressed, "open")
	open_button.tooltip_text = "Open a .blab line file"
	actions.add_child(open_button)
	export_button = Ui.button("Export", _open_export, "export", "Raised")
	actions.add_child(export_button)
	header.add_child(actions)
	return header


func show_page(page: String) -> void:
	line_page.visible = page == "line"
	cast_page.visible = page == "cast"
	vocabulary_page.visible = page == "vocabulary"
	voices_page.visible = page == "voices"
	for k in tabs:
		tabs[k].set_pressed_no_signal(k == page)
	if page == "cast":
		cast_page.show_cast(members, current)
	elif page == "vocabulary":
		vocabulary_page.show_sets(sets)
	elif page == "line":
		line_page.refresh_speaker()
	scroll.scroll_vertical = 0


## Sharp on dense screens; the side panel moves below on narrow ones.
func _layout() -> void:
	var win := get_window()
	var scale := DisplayServer.screen_get_scale()
	if BlabberWeb.available():
		scale = BlabberWeb.pixel_ratio()
	elif OS.has_feature("mobile"):
		scale = maxf(scale, DisplayServer.screen_get_dpi() / 160.0)
	scale = clampf(scale, 1.0, 3.0)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var win_size := test_size if test_size != Vector2i.ZERO else win.size
	win.content_scale_size = Vector2i(Vector2(win_size) / scale)
	var width := win_size.x / scale
	var phone := width < 640.0
	var pad := 12 if phone else 32
	var side := maxi(pad, int(width - 1440) / 2)
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", 8 if phone else 16)
	margin.add_theme_constant_override("margin_bottom", 48)
	header.vertical = width < 760.0
	nav.add_theme_constant_override("separation", 0 if phone else 4)
	header.get_child(0).add_theme_constant_override("separation", 12 if phone else 28)
	header.find_child("Title", true, false).visible = not phone
	for t in tabs.values():
		var st := Ui.box(Ui.CLEAR, 0, Ui.CLEAR, 0, 10 if phone else 16, 10)
		t.add_theme_stylebox_override("normal", st)
		t.add_theme_stylebox_override("hover", st)
		var on := st.duplicate() as StyleBoxFlat
		on.border_color = Ui.ACCENT
		on.border_width_bottom = 2
		t.add_theme_stylebox_override("pressed", on)
		t.add_theme_stylebox_override("hover_pressed", on)
	var narrow := width < 1060.0
	line_page.set_narrow(narrow, phone)
	cast_page.set_narrow(width < 980.0, phone)
	vocabulary_page.set_narrow(width < 980.0, phone)


# --- Characters ----------------------------------------------------------------

func set_current(i: int) -> void:
	current = clampi(i, 0, members.size() - 1)
	line_page.set_member(member())
	if cast_page.visible:
		cast_page.show_cast(members, current)
	if vocabulary_page.visible:
		vocabulary_page.refresh()
	save_soon()


func _add_member() -> void:
	var m := Cast.make_new(Cast.unique_name(members, "New character"), "man", members.size())
	# Sets every character uses are for new ones too.
	m.sets = Cast.shared_sets(members, sets)
	m.apply_sets()
	members.append(m)
	set_current(members.size() - 1)
	show_page("cast")
	cast_page.focus_name()


func _duplicate_member() -> void:
	var m := Cast.copy_member(member(), Cast.unique_name(members, member().speaker.display_name))
	members.insert(current + 1, m)
	set_current(current + 1)
	cast_page.show_cast(members, current)
	cast_page.focus_name()


func _delete_member() -> void:
	if members.size() <= 1:
		return
	var n: String = member().speaker.display_name
	_ask("Delete %s? Lines you already exported keep their own copy." % n, "Delete", func() -> void:
		members.remove_at(current)
		set_current(mini(current, members.size() - 1))
		cast_page.show_cast(members, current)
		_say("Deleted %s." % n))


func _open_voice(v: BlabberVoice, voice_name: String) -> void:
	var m := member()
	var got := _adopt_sets(v)
	if not v.vocabularies.is_empty():
		m.sets = got.sets # A voice without sets keeps the character's.
	m.speaker.voice = v
	if v.sample_bank:
		m.recording = v.sample_bank
		m.set_use_recording(true)
	else:
		m.set_use_recording(false)
	line_page.refresh_speaker()
	save_soon()
	_say("%s now speaks with “%s”.%s" % [m.speaker.display_name, voice_name, _sets_note(got)])


func _next_sample() -> void:
	_sample_i = (_sample_i + 1) % Cast.SAMPLES.size()
	var s: Array = Cast.SAMPLES[_sample_i]
	for i in members.size():
		if members[i].speaker.display_name == s[0]:
			set_current(i)
			break
	line_page.load_source(s[1])


# --- Speaker menu ---------------------------------------------------------------

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			menu.visible = false)
	add_child(menu)


func _open_menu(anchor: Control) -> void:
	for c in menu.get_children():
		c.queue_free()
	var p := PanelContainer.new()
	var st := Ui.box(Color("1c1e25"), 20, Ui.LINE, 1, 14, 14)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 24
	st.shadow_offset = Vector2(0, 12)
	p.add_theme_stylebox_override("panel", st)
	var v := Ui.vbox(12)
	p.add_child(v)
	v.add_child(Ui.eyebrow("Who says this line"))
	var avail := size.x - 24.0
	var cols := 2 if avail > 420.0 else 1
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var w := minf(480.0, avail)
	for i in members.size():
		var c := CastPage.card(members[i], i == current, (w - 28.0 - 10.0 * (cols - 1)) / cols)
		c.pressed.connect(func() -> void:
			menu.visible = false
			set_current(i))
		grid.add_child(c)
	v.add_child(grid)
	var add := Ui.button("New character…", func() -> void:
		menu.visible = false
		_add_member(), "plus", "Link")
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(add)
	menu.add_child(p)
	p.custom_minimum_size.x = w
	p.modulate.a = 0.0 # Shown once it's in place, next frame.
	menu.visible = true
	menu.move_to_front()
	await get_tree().process_frame
	var r := anchor.get_global_rect()
	var pos := Vector2(r.position.x, r.end.y + 8.0)
	pos.x = clampf(pos.x, 12.0, maxf(12.0, size.x - p.size.x - 12.0))
	if pos.y + p.size.y > size.y - 12.0:
		pos.y = maxf(12.0, r.position.y - p.size.y - 8.0)
	p.position = pos
	p.modulate.a = 1.0
	if grid.get_child_count() > current:
		grid.get_child(current).grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if menu.visible and event.is_action_pressed("ui_cancel"):
		menu.visible = false
		get_viewport().set_input_as_handled()


# --- Recording ------------------------------------------------------------------

func _build_recorder() -> void:
	record_sheet = Sheet.new("Record a voice", 620)
	add_child(record_sheet)
	record_hint = Ui.label("", 14, Ui.DIM)
	record_sheet.body.add_child(record_hint)
	studio = SampleStudio.new()
	studio.show_voice_options = false
	studio.handle_drops = false
	record_sheet.body.add_child(studio)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	use_recording_button = Ui.button("Use this recording", _use_studio_recording, "", "Primary")
	row.add_child(use_recording_button)
	row.add_child(Ui.button("Cancel", record_sheet.close))
	record_sheet.body.add_child(row)
	studio.changed.connect(func() -> void: use_recording_button.disabled = studio.bank == null or studio.bank.active_count() == 0)


func _open_recorder() -> void:
	var m := member()
	record_sheet.title_label.text = "Record a voice for %s" % m.speaker.display_name
	record_hint.text = "Read the prompt or make any noises. Blabbermouth cuts the sound into syllables and plays them back at %s’s pitch (%d Hz) and size, so it fits the character." % [m.speaker.display_name, roundi(m.speaker.voice.pitch)]
	studio.reset_for(m.speaker.voice, m.recording)
	use_recording_button.disabled = studio.bank == null
	record_sheet.open()


func _use_studio_recording() -> void:
	if studio.bank == null or studio.bank.active_count() == 0:
		return
	var m := member()
	m.recording = studio.bank
	m.speaker.voice.sample_melody = studio.melody
	m.speaker.voice.sample_variety = studio.variety
	m.set_use_recording(true)
	record_sheet.close()
	line_page.refresh_speaker()
	if cast_page.visible:
		cast_page.show_cast(members, current)
	save_soon()
	_say("%s now speaks with your recording. Switch back any time under the bubble." % m.speaker.display_name)


# --- Export and open ---------------------------------------------------------------

func _build_export() -> void:
	export_sheet = Sheet.new("Export", 600)
	add_child(export_sheet)
	var b := export_sheet.body
	var game := Ui.panel(Ui.CARD, 18, 18, 16)
	var gv := Ui.vbox(10)
	game.add_child(gv)
	gv.add_child(Ui.heading("Line file for games (.blab)"))
	gv.add_child(Ui.label("The words with their effects, plus a copy of the speaker: voice, bubble, font, and the takes of any vocabulary words the line uses. A Godot project with the Blabbermouth plugin loads it as a BlabberLine, and can use the voice, the text styling and the bubble together or one at a time.", 14, Ui.DIM))
	var code := Ui.label("$Dialogue.say(load(\"res://lines/my_line.blab\"))", 13, Ui.TEXT_2)
	code.add_theme_font_override("font", Ui.FONT_MONO)
	gv.add_child(code)
	export_font_check = CheckButton.new()
	export_font_check.button_pressed = true
	gv.add_child(export_font_check)
	gv.add_child(Ui.button("Save line file" if not BlabberWeb.available() else "Download line file", _export_line, "export", "Primary"))
	b.add_child(game)
	var sound := Ui.panel(Ui.CARD, 18, 18, 16)
	var sv := Ui.vbox(10)
	sound.add_child(sv)
	sv.add_child(Ui.heading("Sound file (.wav)"))
	export_note = Ui.label("", 14, Ui.DIM)
	sv.add_child(export_note)
	sv.add_child(Ui.button("Save sound" if not BlabberWeb.available() else "Download sound", _export_wav, "export"))
	b.add_child(sound)
	export_status = Ui.label("", 14, Ui.ACCENT)
	b.add_child(export_status)


func _open_export() -> void:
	var m := member()
	var font: Font = m.speaker.bubble.font
	var kb := 0
	var base: Font = font
	while base is FontVariation and base.base_font:
		base = base.base_font
	if base is FontFile:
		kb = ceili(base.data.size() * 4.0 / 3.0 / 1024.0)
	export_font_check.text = "Include the font (+%d KB), so the bubble looks the same in any game" % kb if kb > 0 else "Include the font"
	export_font_check.disabled = kb == 0
	export_note.text = "%s saying the line, as audio that plays anywhere: other engines, video editors, or a game without Blabbermouth." % m.speaker.display_name
	export_status.text = ""
	export_sheet.open()


## The line file's contents for the current line and speaker.
func line_file_bytes(embed_font: bool) -> PackedByteArray:
	return BlabberLineFile.to_bytes(BlabberLine.create(line_page.model.to_source(), member().speaker), embed_font)


func _file_stem() -> String:
	var who: String = member().speaker.display_name.to_lower().replace(" ", "_")
	var words: PackedStringArray = []
	for w in line_page.model.text.split(" ", false):
		var clean := ""
		for c in w.to_lower():
			if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
				clean += c
		if clean != "":
			words.append(clean)
		if words.size() >= 3:
			break
	var stem := BlabberVoiceFile.clean_name(who + ("_" + "_".join(words) if not words.is_empty() else ""))
	return stem if stem != "" else "line"


func _export_line() -> void:
	var bytes := line_file_bytes(export_font_check.button_pressed and not export_font_check.disabled)
	_save_bytes(bytes, _file_stem() + ".blab", "*.blab ; Blabbermouth line", "application/json")


func _export_wav() -> void:
	if line_page.model.text.strip_edges() == "":
		export_status.text = "Type a line first."
		return
	var tmp := "user://export_tmp.wav"
	var err := line_page.current_line().bake().save_to_wav(tmp)
	if err != OK:
		export_status.text = "Couldn't make the sound (%s)." % error_string(err)
		return
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	_save_bytes(bytes, _file_stem() + ".wav", "*.wav ; WAV sound", "audio/wav")


## Saves or downloads a file. report shows what happened (the export sheet's status by default).
func _save_bytes(bytes: PackedByteArray, file_name: String, filter: String, mime: String, report := Callable()) -> void:
	if not report.is_valid():
		report = func(t: String) -> void: export_status.text = t
	if BlabberWeb.available():
		BlabberWeb.download(bytes, file_name, mime)
		report.call("Downloaded %s." % file_name)
		return
	var d := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, filter)
	d.current_file = file_name
	d.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			report.call("Couldn't save %s (%s)." % [path.get_file(), error_string(FileAccess.get_open_error())])
			return
		f.store_buffer(bytes)
		f.close()
		report.call("Saved " + path), CONNECT_ONE_SHOT)
	d.popup_centered_ratio(0.7)


func _export_set(vs: BlabberVocabulary) -> void:
	if vs:
		_save_bytes(vs.to_bytes(), vs.file_name(), "*.blab ; Blabbermouth vocabulary", "application/json", _say)


## A set from an opened file joins the sets: its words and takes go into the
## set with the same name, or it becomes a new set.
## Returns {set, added (new words x, new takes y), new}.
func _adopt_set(from: BlabberVocabulary) -> Dictionary:
	if sets.has(from):
		return {"set": from, "added": Vector2i.ZERO, "new": false}
	var set_name := from.resource_name if from.resource_name != "" else Cast.DEFAULT_SET_NAME
	var have := Cast.set_named(sets, set_name)
	if have == null:
		from.resource_name = Cast.unique_set_name(sets, set_name)
		Cast.forget_id(from)
		Cast.give_id(from, sets)
		sets.append(from)
		_dirty_sets[from] = true
		return {"set": from, "added": Vector2i(from.words.size(), 0), "new": true}
	var n := Cast.merge_vocabulary(have, from)
	if n != Vector2i.ZERO:
		_dirty_sets[have] = true
	return {"set": have, "added": n, "new": false}


## The sets an opened voice uses, as the editor's sets: copies join them
## (see _adopt_set()) and links are matched by name.
## Returns {sets, missing (names of linked sets the editor doesn't have), new_sets}.
func _adopt_sets(v: BlabberVoice) -> Dictionary:
	var out: Array = []
	var missing: PackedStringArray = []
	var new_sets := 0
	for vs in v.vocabularies:
		var got: BlabberVocabulary = null
		if BlabberVoiceFile.is_link(vs):
			got = Cast.set_named(sets, vs.resource_name if vs.resource_name != "" else BlabberVoiceFile.link_of(vs).get_basename())
			if got == null:
				missing.append(vs.resource_name)
		else:
			var r := _adopt_set(vs)
			got = r.set
			new_sets += 1 if r.new else 0
		if got and not out.has(got):
			out.append(got)
	v.vocabularies.assign(out)
	return {"sets": out, "missing": missing, "new_sets": new_sets}


## For the Voices page: a voice with its linked sets replaced by the editor's.
func _resolve_links(v: BlabberVoice) -> BlabberVoice:
	var c := BlabberVoiceFile.copy_voice(v)
	var out: Array = []
	for vs in c.vocabularies:
		var got: BlabberVocabulary = vs
		if BlabberVoiceFile.is_link(vs):
			got = Cast.set_named(sets, vs.resource_name)
		if got:
			out.append(got)
	c.vocabularies.assign(out)
	return c


## What happened to an opened voice's sets, for the status line.
func _sets_note(got: Dictionary) -> String:
	var note := ""
	if got.new_sets > 0:
		note += " Its recorded words are in %s on the Vocabulary page." % ("a new set" if got.new_sets == 1 else "%d new sets" % got.new_sets)
	if not got.missing.is_empty():
		note += " It uses recorded words you don't have here (%s): open that set's file to add them." % ", ".join(got.missing)
	return note


func _file_dialog(mode: FileDialog.FileMode, filter: String) -> FileDialog:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray([filter])
	add_child(_dialog)
	return _dialog


func _open_pressed() -> void:
	if BlabberWeb.available():
		return # The file input laid over the button opens the picker.
	var d := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.blab ; Blabbermouth line, voice or vocabulary")
	d.file_selected.connect(_open_path, CONNECT_ONE_SHOT)
	d.popup_centered_ratio(0.7)


func _open_path(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_say("Couldn't open %s." % path.get_file())
		return
	if f.get_length() > BlabberVoiceFile.MAX_BYTES:
		_say("%s is too big to be a Blabbermouth file." % path.get_file())
		return
	open_line_bytes(f.get_buffer(f.get_length()), path.get_file())


## Opens a .blab file: a line goes into the editor with its speaker added to
## the characters; a voice file goes to the Voices page; a vocabulary file
## joins the sets of recorded words.
func open_line_bytes(bytes: PackedByteArray, file_name: String) -> void:
	if BlabberVocabulary.is_vocabulary(bytes):
		var vr := BlabberVocabulary.from_bytes(bytes)
		if not vr.ok:
			_say("%s: %s" % [file_name, vr.error])
			return
		var vs: BlabberVocabulary = vr.vocabulary
		if vs.resource_name == "":
			vs.resource_name = BlabberVoiceFile.clean_name(file_name.get_basename())
		var r := _adopt_set(vs)
		if r.new:
			member().set_uses(r.set, true)
		show_page("vocabulary")
		vocabulary_page.show_sets(sets, r.set)
		line_page.refresh_speaker()
		save_soon()
		var added: Vector2i = r.added
		if r.new:
			_say("Opened “%s” as a new set with %d word%s, used by %s. Choose who else uses it below." % [r.set.resource_name, added.x, "" if added.x == 1 else "s", member().speaker.display_name])
		elif added == Vector2i.ZERO:
			_say("Nothing new in %s: “%s” has all its words and takes." % [file_name, r.set.resource_name])
		else:
			_say("Added %s to “%s”: %d new word%s and %d new take%s." % [file_name, r.set.resource_name, added.x, "" if added.x == 1 else "s", added.y, "" if added.y == 1 else "s"])
		return
	if not BlabberLineFile.is_line(bytes):
		show_page("voices")
		library.import_bytes(bytes, file_name)
		return
	var r := BlabberLineFile.from_bytes(bytes)
	if not r.ok:
		_say("%s: %s" % [file_name, r.error])
		return
	var line: BlabberLine = r.line
	if line.speaker and line.speaker.voice:
		var m := Cast.Member.new()
		m.speaker = line.speaker
		m.speaker.display_name = Cast.unique_name(members, line.speaker_name)
		if m.speaker.bubble == null:
			m.speaker.bubble = BlabberBubbleStyle.new()
		var b := m.speaker.bubble
		if b.font:
			var key := Cast.font_by_name(b.font.get_font_name())
			if key != "":
				var keep := b.font_size
				Cast.set_font(b, key)
				b.font_size = keep
		m.kind = "man"
		m.recording = m.speaker.voice.sample_bank
		m.sets = _adopt_sets(m.speaker.voice).sets
		m.set_use_recording(m.recording != null)
		members.append(m)
		current = members.size() - 1
		line_page.set_member(m)
	line_page.load_source(line.text)
	show_page("line")
	save_soon()
	_say("Opened %s%s." % [file_name, (" — %s joined the characters" % member().speaker.display_name) if line.speaker else ""])


func _on_files_dropped(files: PackedStringArray) -> void:
	var path := files[0]
	var ext := path.get_extension().to_lower()
	if ext == BlabberVoiceFile.EXTENSION:
		_open_path(path)
	elif ext in BlabberAudioImport.EXTENSIONS:
		_open_recorder()
		studio.load_path(path)


## Web: one file input over Open and one over the Voices page's Import.
## Either way the result is a .blab file; its contents say which kind.
func _process(_delta: float) -> void:
	BlabberWeb.place_file_input(open_button, open_button.is_visible_in_tree() and not record_sheet.visible and not export_sheet.visible and not menu.visible, Rect2(), "data")
	if BlabberWeb.file_kind() != "data":
		return
	match BlabberWeb.state():
		"reading":
			_say("Reading %s…" % BlabberWeb.file_name())
		"done":
			var n := BlabberWeb.file_name()
			open_line_bytes(BlabberWeb.take_bytes(), n)
		"error":
			_say(BlabberWeb.error())
			BlabberWeb.reset()


# --- Saving -------------------------------------------------------------------------

func save_soon() -> void:
	if _save_timer:
		_save_timer.start()


func save_now() -> void:
	_save_timer.stop()
	var err := Cast.save_state(members, current, line_page.model.to_source(), save_path, sets)
	for vs in _dirty_sets.keys():
		if err != OK:
			break
		if sets.has(vs):
			err = Cast.save_set(vs, save_path)
		if err == OK:
			_dirty_sets.erase(vs)
	if err == OK and _migrated:
		DirAccess.remove_absolute(Cast.old_vocabulary_path(save_path))
		_migrated = false
	if err != OK:
		_say("Couldn't save your work on this device (%s)." % error_string(err))


func _say(text: String) -> void:
	status.text = text
	status.visible = text != ""
	_status_timer.start()


func _ask(question: String, ok_text: String, then: Callable) -> void:
	confirm.dialog_text = question
	confirm.ok_button_text = ok_text
	for c in confirm.confirmed.get_connections():
		confirm.confirmed.disconnect(c.callable)
	confirm.confirmed.connect(then, CONNECT_ONE_SHOT)
	confirm.popup_centered()
