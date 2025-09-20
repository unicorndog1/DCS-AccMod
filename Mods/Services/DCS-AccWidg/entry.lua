declare_plugin("DCS-AccWidg", {
	installed = true,
	dirName = current_mod_path,
	developerName = _(""),
	developerLink = _(""),
	displayName = _("DCS Accessibility Widget"),
	version = "2.2.0.5",
	state = "installed",
	info = _(""),
    load_immediate = true,
	Skins = {
		{ name = "DCS-AccWidg", dir = "Theme" },
	},
	Options = {
		{ name = "DCS-AccWidg", nameId = "DCS-AccWidg", dir = "Options", allow_in_simulation = true; },
	},
})

plugin_done()