extends SceneTree

const GRID_SCENE: PackedScene = preload("res://scenes/deck_library_grid.tscn")
const INSPECTOR_SCENE: PackedScene = preload("res://scenes/card_inspector.tscn")
const Store = preload("res://scripts/deck_profile_store.gd")

var _checks: int = 0
var _failures: int = 0
var _inspection_count: int = 0
var _armed_count: int = 0
var _drag_start_count: int = 0
var _drag_end_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid: Variant = GRID_SCENE.instantiate()
	root.add_child(grid)
	grid.size = Vector2(388.0, 497.0)
	var store: RefCounted = Store.new("user://unused_grid_profile.json")
	var profile: Dictionary = store.create_default_profile()
	grid.set_library_slots(profile["library_slots"])
	await process_frame
	grid.call("_layout_grid")
	await process_frame

	_check(grid.debug_get_pool_size() == 20, "Four-column virtual grid keeps exactly 20 pooled slots")
	var library_margin := grid.get_node_or_null("Body/Margin") as MarginContainer
	var library_scroll := grid.find_child("Scroll", true, false) as ScrollContainer
	_check(library_margin != null and library_scroll != null, "Library reuses the inspector parchment hierarchy")
	if library_scroll != null:
		_check(library_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Library scrollbar stays hidden while scrolling remains enabled")
	var inspector: Variant = INSPECTOR_SCENE.instantiate()
	root.add_child(inspector)
	inspector.set_board_rect(Rect2(Vector2.ZERO, grid.size))
	await process_frame
	var inspector_parchment := inspector.get_node("Parchment") as Control
	_check(
		(grid.get_node("Shadow") as Control).position.is_equal_approx((inspector_parchment.get_node("Shadow") as Control).position)
		and (grid.get_node("Shadow") as Control).size.is_equal_approx((inspector_parchment.get_node("Shadow") as Control).size)
		and (grid.get_node("Body") as Control).position.is_equal_approx((inspector_parchment.get_node("Body") as Control).position)
		and (grid.get_node("Body") as Control).size.is_equal_approx((inspector_parchment.get_node("Body") as Control).size),
		"Library shadow and body exactly match inspector parchment geometry"
	)
	_check(
		(grid.get_node("TopRod") as Control).position.is_equal_approx((inspector_parchment.get_node("TopRod") as Control).position)
		and (grid.get_node("TopRod") as Control).size.is_equal_approx((inspector_parchment.get_node("TopRod") as Control).size)
		and (grid.get_node("BottomRod") as Control).position.is_equal_approx((inspector_parchment.get_node("BottomRod") as Control).position)
		and (grid.get_node("BottomRod") as Control).size.is_equal_approx((inspector_parchment.get_node("BottomRod") as Control).size),
		"Library rods exactly match inspector parchment geometry"
	)
	var top_indices: Array[int] = grid.debug_get_bound_indices()
	_check(top_indices.min() == 0 and top_indices.max() == 19, "Top pool covers five four-card rows without creating all slots")
	var first: Variant = grid.debug_get_bound_slot(0)
	var fourth: Variant = grid.debug_get_bound_slot(3)
	var fifth: Variant = grid.debug_get_bound_slot(4)
	_check(first != null and not first.is_empty(), "First logical slot displays a card")
	_check(fifth != null and fifth.is_empty(), "First slot after the four-card row displays an empty placeholder")
	var hold_scale_overflow: float = first.size.x * (1.035 - 1.0) * 0.5
	var card_shadow_overflow: float = 4.0
	_check(
		first.position.x - hold_scale_overflow - card_shadow_overflow >= 0.0
		and fourth.position.x + fourth.size.x + hold_scale_overflow + card_shadow_overflow <= library_scroll.size.x,
		"Outer cards retain their borders and hold lift inside the clipped scroll viewport"
	)
	var card_host := first.get_node("CardHost") as Control
	_check(
		is_equal_approx(card_host.size.x / card_host.size.y, 0.75),
		"Library card host preserves the standard 3:4 ratio"
	)
	_check(is_equal_approx(first.position.y, 8.0), "First library row starts eight pixels below the scroll origin")

	var color_probe: Variant = fifth
	var color_data: Dictionary = first.card_data.duplicate(true)
	var tier_colors := {
		1: Color("66717a"),
		2: Color("3e7659"),
		3: Color("3f6f9c"),
		4: Color("715a96"),
		5: Color("9a612d"),
		6: Color("963f4a"),
	}
	for tier: int in tier_colors:
		color_data["tier"] = tier
		color_probe.bind(4, color_data)
		_check(
			(color_probe.get_node("Name") as Label).get_theme_color("font_color").is_equal_approx(tier_colors[tier]),
			"Tier %d uses its approved library-name color" % tier
		)
	color_probe.bind(4, {})
	_check(not (color_probe.get_node("Name") as Label).has_theme_color_override("font_color"), "Empty rebind clears recycled tier color")

	grid.set_scroll_offset(grid.debug_get_row_height() * 249.0)
	await process_frame
	var bottom_indices: Array[int] = grid.debug_get_bound_indices()
	_check(999 in bottom_indices, "The final logical slot is reachable")
	_check(grid.debug_get_pool_size() == 20, "Pool size remains constant at the bottom")

	grid.set_scroll_offset(0.0)
	await process_frame
	first = grid.debug_get_bound_slot(0)
	_connect_slot_signals(first)
	first.debug_begin_pointer(Vector2(10.0, 10.0))
	first.debug_end_pointer(Vector2(10.0, 10.0))
	_check(_inspection_count == 1, "Short stationary release inspects occupied card")

	first.debug_begin_pointer(Vector2(10.0, 10.0))
	first.debug_move_pointer(Vector2(10.0, 40.0))
	first.debug_force_hold_timeout()
	first.debug_end_pointer(Vector2(10.0, 40.0))
	_check(_armed_count == 0 and _drag_start_count == 0, "Movement before hold becomes scrolling")

	grid.set_scroll_offset(grid.debug_get_row_height() * 5.0)
	await process_frame
	var offset_before_mouse_swipe: float = grid.get_scroll_offset()
	var swipe_slot: Variant = grid.debug_get_bound_slot(grid.debug_get_bound_indices()[0])
	swipe_slot.debug_begin_pointer(Vector2(10.0, 80.0))
	swipe_slot.debug_move_pointer(Vector2(10.0, 20.0))
	swipe_slot.debug_end_pointer(Vector2(10.0, 20.0))
	_check(grid.get_scroll_offset() > offset_before_mouse_swipe, "Mouse swipe moves the library without global touch emulation")
	grid.set_scroll_offset(0.0)
	await process_frame
	first = grid.debug_get_bound_slot(0)

	first.debug_begin_pointer(Vector2(10.0, 10.0))
	first.debug_force_hold_timeout()
	_check(_armed_count == 1 and first.is_drag_armed(), "Hold arms drag")
	first.debug_end_pointer(Vector2(10.0, 10.0))
	_check(_drag_start_count == 0 and _drag_end_count == 1, "Releasing an armed card without movement cancels the frozen drag")

	first.debug_begin_pointer(Vector2(10.0, 10.0))
	first.debug_force_hold_timeout()
	first.debug_move_pointer(Vector2(12.0, 24.0))
	var dragged_card := first.get_node("CardHost/CardView") as CardView
	var dragged_empty_frame := first.get_node("CardHost/EmptyFrame") as Control
	var dragged_name := first.get_node("Name") as Label
	_check(
		not dragged_card.visible and dragged_empty_frame.visible and not dragged_name.visible,
		"Active library drag leaves a visually empty slot behind"
	)
	first.debug_end_pointer(Vector2(12.0, 24.0))
	_check(_drag_start_count == 1 and _drag_end_count == 2, "Movement after hold completes a drag")
	_check(
		dragged_card.visible and not dragged_empty_frame.visible and dragged_name.visible,
		"Ending an uncommitted drag restores the library card and name"
	)

	grid.refresh_logical_index(0, "")
	_check(first.is_empty(), "Recycled card slot clears to empty state")
	first.debug_begin_pointer(Vector2(10.0, 10.0))
	first.debug_force_hold_timeout()
	first.debug_end_pointer(Vector2(10.0, 10.0))
	_check(_inspection_count == 1 and _armed_count == 2, "Empty slot neither inspects nor arms")

	var previous_offset: float = grid.get_scroll_offset()
	grid.set_interaction_enabled(false)
	grid.set_interaction_enabled(true)
	_check(is_equal_approx(grid.get_scroll_offset(), previous_offset), "Interaction toggling preserves scroll offset")

	grid.queue_free()
	inspector.queue_free()
	await process_frame
	_finish()


func _connect_slot_signals(slot: Variant) -> void:
	slot.inspection_requested.connect(func(_index: int, _data: Dictionary) -> void: _inspection_count += 1)
	slot.drag_armed.connect(func(_index: int, _data: Dictionary) -> void: _armed_count += 1)
	slot.drag_started.connect(func(_index: int, _data: Dictionary, _position: Vector2) -> void: _drag_start_count += 1)
	slot.drag_ended.connect(func(_index: int, _position: Vector2) -> void: _drag_end_count += 1)


func _finish() -> void:
	if _failures == 0:
		print("DECK_LIBRARY_GRID_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error("DECK_LIBRARY_GRID_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
