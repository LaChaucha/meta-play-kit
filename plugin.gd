@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "TtpGuiApi"
const AUTOLOAD_PATH: String = "res://addons/metaplay_kit/runtime/api/ttp_gui_api.gd"

var _registered_autoload: bool = false


func _enter_tree() -> void:
	var setting_name: String = "autoload/%s" % AUTOLOAD_NAME
	if ProjectSettings.has_setting(setting_name):
		var configured_path: String = str(ProjectSettings.get_setting(setting_name))
		configured_path = configured_path.trim_prefix("*")
		if configured_path != AUTOLOAD_PATH:
			push_warning(
				"MetaPlayKit could not register TtpGuiApi because the autoload name is already in use."
			)
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_registered_autoload = true


func _exit_tree() -> void:
	if _registered_autoload:
		remove_autoload_singleton(AUTOLOAD_NAME)
		_registered_autoload = false
