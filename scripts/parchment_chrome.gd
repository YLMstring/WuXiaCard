class_name ParchmentChrome
extends RefCounted


static func apply(
	shadow: Panel,
	body: PanelContainer,
	top_rod: Panel,
	bottom_rod: Panel
) -> void:
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.12, 0.07, 0.04, 0.28)
	shadow_style.set_corner_radius_all(7)
	shadow.add_theme_stylebox_override("panel", shadow_style)

	var parchment_style := StyleBoxFlat.new()
	parchment_style.bg_color = Color("eddbb2")
	parchment_style.border_color = Color("946a3e")
	parchment_style.set_border_width_all(2)
	parchment_style.set_corner_radius_all(5)
	body.add_theme_stylebox_override("panel", parchment_style)

	var rod_style := StyleBoxFlat.new()
	rod_style.bg_color = Color("725033")
	rod_style.border_color = Color("3f2b20")
	rod_style.set_border_width_all(1)
	rod_style.set_corner_radius_all(5)
	top_rod.add_theme_stylebox_override("panel", rod_style)
	bottom_rod.add_theme_stylebox_override("panel", rod_style)
