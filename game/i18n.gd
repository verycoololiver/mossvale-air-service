extends RefCounted
## Device-locale & browser-locale aware Korean / English localization and embedded CJK font loader.

static var _lang: String = ""
static var _font: Font = null


static func is_ko() -> bool:
	if _lang.is_empty():
		_init_lang()
	return _lang == "ko"


static func get_lang() -> String:
	if _lang.is_empty():
		_init_lang()
	return _lang


static func set_lang(next_lang: String) -> void:
	_lang = "ko" if next_lang.to_lower().begins_with("ko") else "en"


static func toggle_lang() -> String:
	set_lang("en" if is_ko() else "ko")
	return _lang


static func _init_lang() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--lang=ko" or arg == "--ko":
			_lang = "ko"
			return
		if arg == "--lang=en" or arg == "--en":
			_lang = "en"
			return
	if OS.has_feature("web"):
		var web_lang := str(JavaScriptBridge.eval("(function(){ try { var p = new URLSearchParams(window.location.search).get('lang'); if (p) return p; return navigator.language || navigator.userLanguage || ''; } catch(e) { return ''; } })()", true)).to_lower()
		if not web_lang.is_empty():
			_lang = "ko" if web_lang.begins_with("ko") else "en"
			return
	var locale := OS.get_locale_language().to_lower()
	if locale.is_empty():
		locale = OS.get_locale().to_lower()
	_lang = "ko" if locale.begins_with("ko") else "en"


static func t(ko_text: String, en_text: String) -> String:
	return ko_text if is_ko() else en_text


static func get_ui_font() -> Font:
	if _font != null:
		return _font
	if ResourceLoader.exists("res://assets/ui_font.ttf"):
		var bundled := load("res://assets/ui_font.ttf") as Font
		if bundled != null:
			_font = bundled
			return _font
	for path in ["C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/malgunbd.ttf"]:
		if FileAccess.file_exists(path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(path) == OK:
				_font = ff
				return _font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Malgun Gothic",
		"Apple SD Gothic Neo",
		"Noto Sans CJK KR",
		"NanumGothic",
		"Segoe UI",
		"Arial"
	])
	_font = sys
	return _font


static func install_default_theme_font() -> Font:
	var font := get_ui_font()
	var theme := ThemeDB.get_project_theme()
	if theme != null and font != null:
		theme.default_font = font
	return font
