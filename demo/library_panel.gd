extends VBoxContainer
## "Library" panel: save voices on this device, open them again, and move
## them between devices with Export and Import (.blab files).

## A saved or imported voice should become the current voice.
signal opened(voice: BlabberVoice, voice_name: String)

## Returns the voice being edited. Set by the demo.
var get_voice: Callable
## Returns the current voice's name, used as the default name when saving.
var get_name_hint: Callable
## Returns a copy of a voice with its linked sets of recorded words replaced
## by the sets themselves, for exports that carry copies. Optional.
var resolve_sets: Callable
## Off: the app reads web file picks and dropped files and passes voice
## files to import_bytes().
var handle_files := true

var name_edit: LineEdit
var list: ItemList
var empty_label: Label
var open_button: Button
var rename_button: Button
var delete_button: Button
var export_button: Button
var copy_words_check: CheckButton
var import_button: Button
var status: Label
var confirm: ConfirmationDialog
var export_dialog: FileDialog
var import_dialog: FileDialog
var godot_dialog: FileDialog
var _on_confirm: Callable
var _asked_persist := false
var _export_bytes := PackedByteArray()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_label("Saved voices", 20, 1.0))
	add_child(_label(_where_text(), 13, 0.6))
	if not BlabberLibrary.is_persistent():
		var warn := _label("This browser isn't keeping saved files (maybe a private window). Use Export to keep your voices.", 13, 1.0)
		warn.modulate = Color(1.0, 0.75, 0.4)
		add_child(warn)

	var srow := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name this voice"
	name_edit.max_length = BlabberVoiceFile.MAX_NAME
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void: _save())
	srow.add_child(name_edit)
	srow.add_child(_button("Save", _save))
	add_child(srow)

	list = ItemList.new()
	list.auto_height = true
	list.custom_minimum_size = Vector2(0, 40)
	list.item_selected.connect(_on_selected)
	list.item_activated.connect(func(_i: int) -> void: _open())
	add_child(list)
	empty_label = _label("No saved voices yet. Make one in the other tabs, name it above and press Save.", 13, 0.5)
	add_child(empty_label)

	var arow := HFlowContainer.new()
	open_button = _button("Open", _open)
	rename_button = _button("Rename", _rename)
	delete_button = _button("Delete", _delete)
	export_button = _button("Export", _export)
	for b in [open_button, rename_button, delete_button, export_button]:
		arow.add_child(b)
	add_child(arow)
	copy_words_check = CheckButton.new()
	copy_words_check.text = "Exports carry copies of the recorded words"
	copy_words_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy_words_check.button_pressed = true
	copy_words_check.tooltip_text = "On: an exported voice file has everything it needs.\nOff: it links to its sets of recorded words by name, so voices that share a set can share one file. Export the sets from the Vocabulary page and keep them in the same folder."
	add_child(copy_words_check)

	add_child(HSeparator.new())
	add_child(_label("Other devices", 16, 1.0))
	add_child(_label("To move a voice, Export it here (you get a .blab file), send the file to the other device any way you like, then Import it there. Voice files contain no code, so they are safe to share.", 13, 0.6))
	var irow := HFlowContainer.new()
	import_button = _button("Import voice file…", _import)
	irow.add_child(import_button)
	irow.add_child(_button("Download .tres for Godot" if BlabberWeb.available() else "Save .tres for Godot", _save_for_godot))
	add_child(irow)
	if not BlabberWeb.available():
		add_child(_label("Tip: you can also drop a .blab file on the window.", 13, 0.5))

	status = _label("", 13, 0.7)
	add_child(status)

	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(func() -> void: _on_confirm.call())
	add_child(confirm)

	get_window().files_dropped.connect(func(files: PackedStringArray) -> void:
		if handle_files and files[0].get_extension().to_lower() == BlabberVoiceFile.EXTENSION:
			_import_path(files[0]))
	# On the web, _process keeps the Import file input lined up with its button.
	set_process(BlabberWeb.available())
	refresh()


func _process(_delta: float) -> void:
	var clip := Rect2()
	var p := get_parent()
	if p is Control:
		clip = (p as Control).get_global_rect()
	BlabberWeb.place_file_input(import_button, import_button.is_visible_in_tree(), clip, "data")
	if not handle_files or BlabberWeb.file_kind() != "data":
		return # An audio file for the "My voice" panel.
	match BlabberWeb.state():
		"reading":
			status.text = "Reading %s…" % BlabberWeb.file_name()
		"done":
			var file_name := BlabberWeb.file_name()
			_import_bytes(BlabberWeb.take_bytes(), file_name)
		"error":
			status.text = BlabberWeb.error()
			BlabberWeb.reset()


## Reloads the list of saved voices. Selects the voice at select_path if given.
func refresh(select_path := "") -> void:
	list.clear()
	for e in BlabberLibrary.list():
		var i := list.add_item(e.name + ("   (recording)" if e.has_recording else ""))
		list.set_item_metadata(i, e.path)
		list.set_item_tooltip(i, "Saved " + Time.get_datetime_string_from_unix_time(e.modified, true))
		if e.path == select_path:
			list.select(i)
	empty_label.visible = list.item_count == 0
	_update_buttons()


## Puts a name in the name box and focuses it, ready to save.
func focus_name(voice_name: String) -> void:
	if name_edit.text.strip_edges() == "":
		name_edit.text = voice_name
	name_edit.grab_focus()
	name_edit.select_all()


func _where_text() -> String:
	if BlabberWeb.available():
		return "Saved voices stay in this browser on this device. Clearing the browser's site data deletes them."
	if OS.has_feature("mobile"):
		return "Saved voices stay on this device. Uninstalling the app deletes them."
	return "Saved voices are kept in " + ProjectSettings.globalize_path(BlabberLibrary.folder)


func _selected_path() -> String:
	var sel := list.get_selected_items()
	return list.get_item_metadata(sel[0]) if not sel.is_empty() else ""


func _selected_name() -> String:
	return _selected_path().get_file().get_basename()


func _update_buttons() -> void:
	var none := _selected_path() == ""
	for b in [open_button, rename_button, delete_button, export_button]:
		b.disabled = none


func _on_selected(_i: int) -> void:
	name_edit.text = _selected_name()
	_update_buttons()


func _typed_name() -> String:
	var n := name_edit.text.strip_edges()
	if n == "" and get_name_hint.is_valid():
		n = get_name_hint.call()
	return BlabberVoiceFile.clean_name(n)


func _ask(question: String, ok_text: String, then: Callable) -> void:
	confirm.dialog_text = question
	confirm.ok_button_text = ok_text
	_on_confirm = then
	confirm.popup_centered()


func _save() -> void:
	var n := _typed_name()
	if n == "":
		status.text = "Type a name for the voice first."
		name_edit.grab_focus()
		return
	if BlabberLibrary.has(n):
		_ask("A voice called \"%s\" is already saved. Replace it?" % n, "Replace", func() -> void: _do_save(n))
	else:
		_do_save(n)


func _do_save(n: String) -> void:
	if not _asked_persist:
		# Asked on a tap, which is when browsers are most willing to agree.
		BlabberLibrary.request_persistent_storage()
		_asked_persist = true
	# Saved voices link to the editor's sets instead of copying them.
	var r := BlabberLibrary.save(get_voice.call(), n, true)
	if not r.ok:
		status.text = r.error
		return
	refresh(r.path)
	name_edit.text = r.name
	status.text = "Saved \"%s\"." % r.name


func _open() -> void:
	var path := _selected_path()
	if path == "":
		return
	var r := BlabberLibrary.open(path)
	if not r.ok:
		status.text = r.error
		return
	opened.emit(r.voice, r.name)
	status.text = "Opened \"%s\"." % r.name


func _rename() -> void:
	var path := _selected_path()
	var n := BlabberVoiceFile.clean_name(name_edit.text)
	if path == "":
		return
	if n == "":
		status.text = "Type the new name in the box above, then press Rename."
		name_edit.grab_focus()
		return
	var old_name := _selected_name()
	var r := BlabberLibrary.rename(path, n)
	if not r.ok:
		status.text = r.error
		return
	refresh(r.path)
	status.text = "Renamed \"%s\" to \"%s\"." % [old_name, r.name]


func _delete() -> void:
	var path := _selected_path()
	if path == "":
		return
	var n := _selected_name()
	_ask("Delete \"%s\"? This can't be undone." % n, "Delete", func() -> void:
		var err := BlabberLibrary.remove(path)
		refresh()
		status.text = ("Deleted \"%s\"." % n) if err == OK else "Could not delete (%s)." % error_string(err))


func _export() -> void:
	var path := _selected_path()
	if path == "":
		return
	var r := BlabberLibrary.open(path)
	if not r.ok:
		status.text = r.error
		return
	var file_name: String = r.name + "." + BlabberVoiceFile.EXTENSION
	var copy := copy_words_check.button_pressed
	var voice: BlabberVoice = r.voice
	if copy and resolve_sets.is_valid():
		voice = resolve_sets.call(voice)
	_export_bytes = BlabberVoiceFile.to_bytes(voice, r.name, not copy)
	if BlabberWeb.available():
		BlabberWeb.download(_export_bytes, file_name)
		status.text = "Downloaded %s. Import it on the other device." % file_name
		return
	if export_dialog == null:
		export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.blab ; Blabbermouth voice")
		export_dialog.file_selected.connect(func(p: String) -> void:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f == null:
				status.text = "Could not write %s (%s)." % [p.get_file(), error_string(FileAccess.get_open_error())]
				return
			f.store_buffer(_export_bytes)
			f.close()
			status.text = "Exported to " + p)
	export_dialog.current_file = file_name
	export_dialog.popup_centered_ratio(0.7)


func _import() -> void:
	if BlabberWeb.available():
		return # The file input laid over the button handles the tap.
	if import_dialog == null:
		import_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.blab ; Blabbermouth voice")
		import_dialog.file_selected.connect(_import_path)
	import_dialog.popup_centered_ratio(0.7)


func _import_path(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		status.text = "Could not open %s." % path.get_file()
		return
	if f.get_length() > BlabberVoiceFile.MAX_BYTES:
		status.text = "%s is too big to be a voice file." % path.get_file()
		return
	_import_bytes(f.get_buffer(f.get_length()), path.get_file())


## Adds an imported voice to the library and opens it.
func import_bytes(bytes: PackedByteArray, file_name: String) -> void:
	_import_bytes(bytes, file_name)


func _import_bytes(bytes: PackedByteArray, file_name: String) -> void:
	var r := BlabberVoiceFile.from_bytes(bytes, file_name.get_basename())
	if not r.ok:
		status.text = "%s: %s" % [file_name, r.error]
		return
	var n := BlabberLibrary.unique_name(r.name)
	# Opened first, so its recorded words join the editor's sets, which the
	# saved voice then links to.
	opened.emit(r.voice, n)
	var saved := BlabberLibrary.save(r.voice, n, true)
	if not saved.ok:
		status.text = saved.error
		return
	refresh(saved.path)
	name_edit.text = saved.name
	status.text = "Imported and opened \"%s\"." % saved.name


## A Godot resource, for game projects. Voices with a recording use binary
## .res, which keeps them small. Only open .tres/.res files you trust: unlike
## .blab files, they can contain code.
func _save_for_godot() -> void:
	var voice: BlabberVoice = get_voice.call()
	var n := _typed_name()
	if n == "":
		n = "voice"
	var big := voice.sample_bank != null
	for vs in voice.vocabularies:
		big = big or not vs.lookup().is_empty()
	var ext := "res" if big else "tres"
	if BlabberWeb.available():
		var tmp := "user://%s.%s" % [n, ext]
		var err := ResourceSaver.save(voice, tmp)
		if err != OK:
			status.text = "Save failed (%s)" % error_string(err)
			return
		BlabberWeb.download(FileAccess.get_file_as_bytes(tmp), tmp.get_file())
		DirAccess.remove_absolute(tmp)
		status.text = "Downloaded %s. Put it in your Godot project and use it as a voice." % tmp.get_file()
		return
	if godot_dialog == null:
		godot_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "")
		godot_dialog.file_selected.connect(func(p: String) -> void:
			var err := ResourceSaver.save(get_voice.call(), p)
			status.text = ("Saved " + p) if err == OK else "Save failed (%s)" % error_string(err))
	godot_dialog.filters = PackedStringArray(["*.%s ; Godot voice resource" % ext])
	godot_dialog.current_file = "%s.%s" % [n, ext]
	godot_dialog.popup_centered_ratio(0.7)


func _file_dialog(mode: FileDialog.FileMode, filter: String) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	if filter != "":
		d.filters = PackedStringArray([filter])
	add_child(d)
	return d


func _label(t: String, font_size: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = Color(1, 1, 1, alpha)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b
