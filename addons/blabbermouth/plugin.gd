@tool
extends EditorPlugin
## The node and voice classes work without enabling the plugin (they use
## class_name). Enabling it in Project Settings > Plugins adds the .blab
## importer, so voice files in your project become BlabberVoice resources.

const ImportPlugin := preload("res://addons/blabbermouth/blabber_import_plugin.gd")

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = ImportPlugin.new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
