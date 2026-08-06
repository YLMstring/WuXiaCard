extends SceneTree

const DUEL_SCENE: PackedScene = preload("res://scenes/duel.tscn")
const CARD_SCENE: PackedScene = preload("res://scenes/card_view.tscn")
const CARD_SCRIPT: Script = preload("res://scripts/card_view.gd")
const Catalog = preload("res://scripts/card_catalog.gd")
const Decks = preload("res://scripts/duel_decks.gd")
const Rules = preload("res://scripts/duel_rules.gd")
const Backdrop = preload("res://scripts/duel_backdrop.gd")
const TEST_PROFILE_PATH: String = "user://duel_integration_deck_test.json"

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_test_profile()
	var duel: Node = _instantiate_duel()
	root.add_child(duel)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(duel.debug_get_search_budget_seconds()), 10.0), "Shen Lian defaults to the hard 10-second search profile")
	duel.debug_set_fast_mode(true)

	_check_layout(duel)
	_check_duel_canvas_structure(duel)
	await _check_attack_vfx_overlay(duel)
	await _check_fixed_duel_canvas_geometry(duel)
	await _check_duel_header(duel)
	_check_card_edge_labels(duel)
	await _check_card_picture_layout()
	_check_hand_slots(duel.get_node("DuelCanvas/PlayerHand"))
	_check_hand_slots(duel.get_node("DuelCanvas/OpponentHand"))
	_check_catalog_hands(duel)
	_check_side_deck_setup(duel)
	await _check_duplicate_enemy_instances()
	_check_normal_opponent_concealment(duel)
	await _check_card_inspector_modal()
	await _check_inspector_holds_completed_ai_move()
	await _check_focus_loss_return()
	await _check_dragged_card_commits_through_simulator()
	await _check_aspect_ratio_input_paths()
	await _check_testing_mode_manual_turns()
	await _check_player_gate_exile()
	await _check_opponent_tiger_exile()
	await _check_cangsong_reaction_presentation()
	await _check_player_draw_and_instance_mapping()
	await _check_opponent_draw_visibility()
	await _check_manual_activate_move()
	await _check_meng_huo_extra_turn_presentation()
	await _check_ability_pulse_sequencing()
	var initial_player_card_sizes: Dictionary = _card_sizes_by_slot(duel.get_node("DuelCanvas/PlayerHand"))

	var player_turns: int = 0
	while not duel.debug_is_complete() and player_turns < 20:
		var target_cell: int = duel.debug_first_empty_cell()
		var placed: bool = await duel.debug_place_player_card(0, target_cell)
		_check(placed, "Player turn %d commits through the production move path" % (player_turns + 1))
		player_turns += 1
		if player_turns == 1:
			await process_frame
			_check_hand_slots(duel.get_node("DuelCanvas/PlayerHand"))
			_check_remaining_card_sizes(duel.get_node("DuelCanvas/PlayerHand"), initial_player_card_sizes)

	var scores: Vector2i = duel.debug_get_scores()
	var search_report: Dictionary = duel.debug_get_last_search_report()
	_check(int(search_report.get("completed_depth", 0)) >= 1, "Normal opponent turns publish completed smart-search telemetry")
	_check(not bool(search_report.get("used_fallback", true)), "Fast deterministic integration search completes without fallback")
	var occupancy: int = duel.debug_get_board_occupancy()
	var simulation_turns: int = duel.debug_get_simulation_turn_count()
	var remaining_cards: int = _count_cards(duel.get_node("DuelCanvas/PlayerHand")) + _count_cards(duel.get_node("DuelCanvas/OpponentHand"))
	_check(duel.debug_is_complete(), "Scripted match reaches the complete state")
	_check(scores.x + scores.y == occupancy, "Final scores count exactly the cards remaining on board")
	_check(player_turns <= 20, "Scripted match remains within the safety turn bound")
	_check(duel.has_method("debug_get_simulation_turn_count"), "Production duel exposes simulator turn-count diagnostics")
	if duel.has_method("debug_get_simulation_turn_count"):
		var removed_cards: int = duel.debug_get_removed_count(Rules.PLAYER_OWNER) + duel.debug_get_removed_count(Rules.OPPONENT_OWNER)
		_check(simulation_turns >= occupancy + removed_cards, "Action turns account for every card that entered the board")
	var expected_total_cards: int = _expected_total_card_count()
	_check(
		duel.debug_get_total_card_count() == expected_total_cards,
		"All main-deck and owner-derived side-deck instances remain accounted for"
	)
	_check(remaining_cards <= 10, "Both fixed hands remain within their five-card limits")
	_check(not duel.has_node("Arrow"), "Approved layout contains no right-side arrow")
	var opponent_name := duel.get_node("DuelCanvas/TopBar/OpponentName") as Label
	var exit_button := duel.get_node("DuelCanvas/TopBar/ExitButton") as Button
	_check(not opponent_name.text.is_empty() and opponent_name.get_index() < exit_button.get_index(), "Opponent name appears in the upper-left top bar")
	_check(
		exit_button.text.is_empty()
		and exit_button.icon != null
		and exit_button.get_index() > opponent_name.get_index(),
		"Icon-only return control appears in the upper-right top bar"
	)

	duel.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures == 0:
		print("DUEL_INTEGRATION_PASSED checks=%d player=%d opponent=%d" % [_checks, scores.x, scores.y])
	else:
		push_error("DUEL_INTEGRATION_FAILED failures=%d checks=%d" % [_failures, _checks])
	quit(_failures)


func _check_layout(duel: Node) -> void:
	var canvas := duel.get_node("DuelCanvas") as Control
	var opponent_hand := duel.get_node("DuelCanvas/OpponentHand") as HBoxContainer
	var player_hand := duel.get_node("DuelCanvas/PlayerHand") as HBoxContainer
	var board_grid := duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as GridContainer
	var turn_status := duel.get_node("DuelCanvas/TurnStatus") as Label
	var top_gap: float = board_grid.position.y - (opponent_hand.position.y + opponent_hand.size.y)
	var bottom_gap: float = player_hand.position.y - (board_grid.position.y + board_grid.size.y)
	var board_center_x: float = board_grid.position.x + board_grid.size.x * 0.5
	_check(absf(top_gap - bottom_gap) < 1.0, "Board has equal spacing to opponent and player hands")
	_check(absf(board_center_x - canvas.size.x * 0.5) < 1.0, "Board remains horizontally centered")
	_check(absf(board_grid.size.x / board_grid.size.y - duel.board_aspect_ratio) < 0.01, "Board preserves the approved portrait-cell aspect ratio")
	_check(turn_status.position.y >= player_hand.position.y + player_hand.size.y, "Turn status appears below the player hand")
	_check(absf(turn_status.position.x - player_hand.position.x) < 1.0 and absf(turn_status.size.x - player_hand.size.x) < 1.0, "Turn status matches the player hand's horizontal bounds")
	_check(turn_status.position.y + turn_status.size.y <= canvas.size.y - 8.0, "Turn status remains inside the bottom safe area")


func _check_duel_canvas_structure(duel: Node) -> void:
	var backdrop: Control = duel.get_node_or_null("DecorBackdrop") as Control
	var canvas: Control = duel.get_node_or_null("DuelCanvas") as Control
	_check(
		backdrop != null
		and backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Decorative backdrop exists and cannot intercept input"
	)
	_check(canvas != null, "Fixed duel canvas exists")
	if backdrop == null or canvas == null:
		return
	_check(
		backdrop.get_index() < canvas.get_index(),
		"Decorative backdrop renders behind the duel canvas"
	)
	for node_path: String in [
		"TopWash",
		"BoardCenter",
		"TopBar",
		"OpponentHand",
		"PlayerHand",
		"ScoreOverlay",
		"TurnStatus",
		"AttackVfx",
		"ExtraTurnVfx",
		"DragLayer",
		"CardInspector",
	]:
		_check(
			canvas.has_node(node_path),
			"%s is contained by the fixed duel canvas" % node_path
		)
	for audio_path: String in [
		"PlacementAudio",
		"CaptureAudio",
		"RemovalAudio",
		"MovementAudio",
	]:
		_check(
			duel.has_node(audio_path)
			and duel.get_node(audio_path).get_parent() == duel,
			"%s remains a non-visual root child" % audio_path
		)


func _check_attack_vfx_overlay(duel: Node) -> void:
	var attack_vfx: Control = duel.get_node_or_null("DuelCanvas/AttackVfx") as Control
	var extra_turn_vfx: Control = duel.get_node("DuelCanvas/ExtraTurnVfx") as Control
	var drag_layer: Control = duel.get_node("DuelCanvas/DragLayer") as Control
	_check(attack_vfx != null, "Duel scene contains the reusable attack VFX overlay")
	if attack_vfx == null:
		return
	_check(
		attack_vfx.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Attack VFX never intercepts mouse or touch input"
	)
	_check(
		attack_vfx.z_index < extra_turn_vfx.z_index
		and attack_vfx.z_index < drag_layer.z_index,
		"Attack VFX renders below extra-turn, drag, and modal presentation"
	)
	_check(
		attack_vfx.size.is_equal_approx(
			duel.get_node("DuelCanvas").size
		),
		"Attack VFX covers the complete fixed duel canvas"
	)
	var has_asset_api: bool = (
		attack_vfx.has_method("play_attack")
		and attack_vfx.has_method("debug_get_last_center")
		and attack_vfx.has_method("debug_get_last_rotation")
		and attack_vfx.has_method("debug_get_display_size")
		and attack_vfx.has_method("debug_get_texture_path")
		and attack_vfx.has_method("debug_get_clip_size")
		and attack_vfx.has_method("debug_is_clean")
	)
	_check(
		has_asset_api,
		"Attack overlay exposes asset-backed playback diagnostics"
	)
	if not has_asset_api:
		return

	var effect_root: Control = attack_vfx.get_node_or_null("EffectRoot") as Control
	var clip: Control = attack_vfx.get_node_or_null("EffectRoot/Clip") as Control
	var texture_rect: TextureRect = (
		attack_vfx.get_node_or_null("EffectRoot/Clip/Texture") as TextureRect
	)
	_check(
		effect_root != null and clip != null and texture_rect != null,
		"Attack overlay owns one reusable clip and texture hierarchy"
	)
	if effect_root == null or clip == null or texture_rect == null:
		return
	_check(
		String(attack_vfx.call("debug_get_texture_path"))
		== "res://inkpics/attack.png",
		"Attack overlay uses the supplied attack.png resource"
	)
	_check(
		(attack_vfx.call("debug_get_display_size") as Vector2).is_equal_approx(
			Vector2(64.0, 22.0)
		)
		and texture_rect.size.is_equal_approx(Vector2(64.0, 22.0))
		and texture_rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"Supplied texture uses the approved 64 by 22 keep-aspect display box"
	)
	_check(
		clip.clip_contents
		and clip.position.is_equal_approx(Vector2.ZERO),
		"Reveal clip keeps its local left edge fixed"
	)

	attack_vfx.call("_set_reveal_progress", 0.5)
	_check(
		(attack_vfx.call("debug_get_clip_size") as Vector2).is_equal_approx(
			Vector2(32.0, 22.0)
		)
		and clip.position.is_equal_approx(Vector2.ZERO),
		"Half reveal grows from local x zero toward the local right"
	)

	var center_local := Vector2(200.0, 360.0)
	var rotation_cases: Array[Dictionary] = [
		{"name": "right", "rotation": 0.0},
		{"name": "left", "rotation": PI},
		{"name": "down", "rotation": PI / 2.0},
		{"name": "up", "rotation": -PI / 2.0},
	]
	for case: Dictionary in rotation_cases:
		await attack_vfx.call(
			"play_attack",
			_local_point_to_global(attack_vfx, center_local),
			float(case["rotation"]),
			0.0
		)
		_check(
			(attack_vfx.call("debug_get_last_center") as Vector2).is_equal_approx(
				center_local
			)
			and is_equal_approx(
				float(attack_vfx.call("debug_get_last_rotation")),
				float(case["rotation"])
			),
			"%s attack preserves its seam center and approved rotation"
			% case["name"]
		)
		_check(
			bool(attack_vfx.call("debug_is_clean")),
			"%s zero-duration bitmap attack leaves no residual visual"
			% case["name"]
		)

	_check_attack_vfx_placement(duel)


func _local_point_to_global(control: Control, local_point: Vector2) -> Vector2:
	var transform: Transform2D = control.get_global_transform_with_canvas()
	return transform * local_point


func _check_attack_vfx_placement(duel: Node) -> void:
	var has_placement_api: bool = duel.has_method("debug_get_attack_vfx_placement")
	_check(
		has_placement_api,
		"Duel controller exposes focused first-seam placement diagnostics"
	)
	if not has_placement_api:
		return

	var right_adjacent: Dictionary = duel.call("debug_get_attack_vfx_placement", 0, 1)
	var right_far: Dictionary = duel.call("debug_get_attack_vfx_placement", 0, 2)
	var left_far: Dictionary = duel.call("debug_get_attack_vfx_placement", 2, 0)
	var down_adjacent: Dictionary = duel.call("debug_get_attack_vfx_placement", 0, 3)
	var down_far: Dictionary = duel.call("debug_get_attack_vfx_placement", 0, 6)
	var up_far: Dictionary = duel.call("debug_get_attack_vfx_placement", 6, 0)

	var cell0: Control = duel.get_node("DuelCanvas/BoardCenter/BoardGrid/Cell0")
	var cell1: Control = duel.get_node("DuelCanvas/BoardCenter/BoardGrid/Cell1")
	var cell3: Control = duel.get_node("DuelCanvas/BoardCenter/BoardGrid/Cell3")
	var cell0_rect: Rect2 = cell0.get_global_rect()
	var cell1_rect: Rect2 = cell1.get_global_rect()
	var cell3_rect: Rect2 = cell3.get_global_rect()
	var expected_right_center := Vector2(
		(cell0_rect.end.x + cell1_rect.position.x) * 0.5,
		(cell0_rect.get_center().y + cell1_rect.get_center().y) * 0.5
	)
	var expected_down_center := Vector2(
		(cell0_rect.get_center().x + cell3_rect.get_center().x) * 0.5,
		(cell0_rect.end.y + cell3_rect.position.y) * 0.5
	)
	_check(
		not right_adjacent.is_empty()
		and (right_adjacent.get("center", Vector2.ZERO) as Vector2).is_equal_approx(
			expected_right_center
		)
		and int(right_adjacent.get("neighbor_cell", -1)) == 1
		and is_equal_approx(float(right_adjacent.get("rotation", INF)), 0.0),
		"Right attack centers the bitmap on the first horizontal seam"
	)
	_check(
		not down_adjacent.is_empty()
		and (down_adjacent.get("center", Vector2.ZERO) as Vector2).is_equal_approx(
			expected_down_center
		)
		and int(down_adjacent.get("neighbor_cell", -1)) == 3
		and is_equal_approx(
			float(down_adjacent.get("rotation", INF)),
			PI / 2.0
		),
		"Down attack centers the bitmap on the first vertical seam"
	)
	_check(
		not right_far.is_empty()
		and (right_far.get("center", Vector2.ZERO) as Vector2).is_equal_approx(
			right_adjacent.get("center", Vector2.ZERO)
		)
		and int(right_far.get("neighbor_cell", -1)) == 1
		and is_equal_approx(
			float(right_far.get("rotation", INF)),
			float(right_adjacent.get("rotation", -INF))
		),
		"Far same-row target keeps the bitmap on the first empty-neighbor seam"
	)
	_check(
		not down_far.is_empty()
		and (down_far.get("center", Vector2.ZERO) as Vector2).is_equal_approx(
			down_adjacent.get("center", Vector2.ZERO)
		)
		and int(down_far.get("neighbor_cell", -1)) == 3
		and is_equal_approx(
			float(down_far.get("rotation", INF)),
			float(down_adjacent.get("rotation", -INF))
		),
		"Far same-column target keeps the bitmap on the first empty-neighbor seam"
	)
	_check(
		int(left_far.get("neighbor_cell", -1)) == 1
		and is_equal_approx(float(left_far.get("rotation", INF)), PI),
		"Left attack rotates the supplied attacker side by 180 degrees"
	)
	_check(
		int(up_far.get("neighbor_cell", -1)) == 3
		and is_equal_approx(float(up_far.get("rotation", INF)), -PI / 2.0),
		"Up attack rotates the supplied attacker side by negative 90 degrees"
	)
	_check(
		(duel.call("debug_get_attack_vfx_placement", 0, 0) as Dictionary).is_empty()
		and (duel.call("debug_get_attack_vfx_placement", 0, 4) as Dictionary).is_empty()
		and (duel.call("debug_get_attack_vfx_placement", -1, 0) as Dictionary).is_empty()
		and (duel.call("debug_get_attack_vfx_placement", 0, 9) as Dictionary).is_empty(),
		"Equal, diagonal, and out-of-range placement inputs are rejected"
	)


func _check_fixed_duel_canvas_geometry(duel: Node) -> void:
	var original_window_size: Vector2i = root.size
	var target_sizes: Array[Vector2i] = [
		Vector2i(540, 960),
		Vector2i(405, 900),
		Vector2i(1280, 839),
	]
	var expected_modes: Array[int] = [
		Backdrop.LayoutMode.MODE_EXACT,
		Backdrop.LayoutMode.MODE_TALL,
		Backdrop.LayoutMode.MODE_WIDE,
	]
	for target_index: int in range(target_sizes.size()):
		var target_size: Vector2i = target_sizes[target_index]
		root.size = target_size
		await process_frame
		duel.call("_layout_duel")
		await process_frame
		var backdrop: Control = duel.get_node("DecorBackdrop") as Control
		var canvas: Control = duel.get_node("DuelCanvas") as Control
		_check(
			absf(canvas.size.x / canvas.size.y - 9.0 / 16.0) < 0.001,
			"Duel canvas remains 9:16 at %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			(canvas.position + canvas.size * 0.5).is_equal_approx(duel.size * 0.5),
			"Duel canvas remains centered at %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			backdrop.position.is_equal_approx(Vector2.ZERO)
			and backdrop.size.is_equal_approx(duel.size),
			"Decorative backdrop fills the viewport at %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			int(backdrop.call("debug_get_layout_mode")) == expected_modes[target_index],
			"Backdrop selects the expected mode at %dx%d" % [target_size.x, target_size.y]
		)
		if target_index == 0:
			_check(
				canvas.position.is_equal_approx(Vector2.ZERO)
				and canvas.size.is_equal_approx(duel.size),
				"Exact 9:16 viewport exposes no extension"
			)
		elif target_index == 1:
			_check(
				is_equal_approx(canvas.position.x, 0.0)
				and is_equal_approx(canvas.size.x, duel.size.x)
				and canvas.position.y > 0.0
				and canvas.position.y + canvas.size.y < duel.size.y,
				"Tall viewport exposes only top and bottom extensions"
			)
		else:
			_check(
				is_equal_approx(canvas.position.y, 0.0)
				and is_equal_approx(canvas.size.y, duel.size.y)
				and canvas.position.x > 0.0
				and canvas.position.x + canvas.size.x < duel.size.x,
				"Wide viewport exposes only left and right extensions"
			)
		_check_layout(duel)
	root.size = original_window_size
	await process_frame
	duel.call("_layout_duel")
	await process_frame


func _check_duel_header(duel: Node) -> void:
	_check(
		ProjectSettings.get_setting("display/window/stretch/aspect", "keep") == "expand",
		"Project expands its logical viewport instead of letterboxing tall phones"
	)
	var top_wash: Control = duel.get_node("DuelCanvas/TopWash") as Control
	var center_tint: TextureRect = duel.get_node_or_null("DuelCanvas/TopWash/CenterTint") as TextureRect
	var bottom_edge: ColorRect = duel.get_node_or_null("DuelCanvas/TopWash/BottomEdge") as ColorRect
	var header_shadow: ColorRect = duel.get_node_or_null("DuelCanvas/TopWash/Shadow") as ColorRect
	var top_bar: HBoxContainer = duel.get_node("DuelCanvas/TopBar") as HBoxContainer
	var enemy_seal: PanelContainer = duel.get_node_or_null("DuelCanvas/TopBar/EnemySeal") as PanelContainer
	var opponent_name: Label = duel.get_node("DuelCanvas/TopBar/OpponentName") as Label
	var exit_button: Button = duel.get_node("DuelCanvas/TopBar/ExitButton") as Button

	_check(
		top_wash is ColorRect
		and center_tint != null
		and bottom_edge != null
		and header_shadow != null,
		"Duel header uses layered ink tint, lower edge, and shadow presentation"
	)
	_check(
		center_tint != null
		and center_tint.stretch_mode == TextureRect.STRETCH_SCALE,
		"Duel header scales the shared tint across its full width without aspect cropping"
	)
	if center_tint != null and center_tint.texture is GradientTexture2D:
		var expected_tint: GradientTexture2D = Backdrop.create_lacquer_tint_texture(540)
		var actual_tint := center_tint.texture as GradientTexture2D
		_check(
			actual_tint.gradient.offsets == expected_tint.gradient.offsets
			and actual_tint.gradient.colors == expected_tint.gradient.colors,
			"Duel header uses the shared lacquer tint definition"
		)
	else:
		_check(false, "Duel header uses the shared lacquer tint definition")
	_check(enemy_seal != null, "Duel header contains the approved enemy seal")
	if enemy_seal != null:
		_check(
			enemy_seal.get_index() < opponent_name.get_index()
			and opponent_name.get_index() < exit_button.get_index(),
			"Enemy seal, opponent name, and exit button remain ordered left to right"
		)
		_check(
			is_equal_approx(enemy_seal.size.x, enemy_seal.size.y)
			and enemy_seal.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Enemy seal stays square and cannot intercept input"
		)
	_check(
		(opponent_name.size_flags_horizontal & Control.SIZE_EXPAND) != 0
		and opponent_name.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"Opponent name expands and trims long names with an ellipsis"
	)
	_check(
		exit_button.focus_mode != Control.FOCUS_NONE
		and exit_button.size.y >= 44.0,
		"Exit button remains focusable with at least a 44-pixel touch target"
	)
	_check(
		exit_button.custom_minimum_size.is_equal_approx(Vector2(44.0, 44.0))
		and exit_button.tooltip_text.is_empty(),
		"Icon-only return control keeps its square mobile target without text chrome"
	)
	_check(
		exit_button.get_theme_stylebox("normal") is StyleBoxEmpty
		and exit_button.get_theme_stylebox("hover") is StyleBoxEmpty
		and exit_button.get_theme_stylebox("pressed") is StyleBoxEmpty
		and exit_button.get_theme_stylebox("hover_pressed") is StyleBoxEmpty
		and exit_button.get_theme_stylebox("disabled") is StyleBoxEmpty
		and exit_button.get_theme_stylebox("focus") is StyleBoxEmpty,
		"Icon-only return control has no visible button chrome"
	)
	_check(
		exit_button.pressed.is_connected(Callable(duel, "_on_exit_pressed")),
		"Icon-only return control keeps the existing exit action"
	)
	if top_wash is ColorRect:
		var header_color: Color = (top_wash as ColorRect).color
		_check(
			header_color.is_equal_approx(Backdrop.LACQUER_COLOR),
			"Duel header and decorative extension share one lacquer color"
		)
		_check(
			header_color.get_luminance() < Color("8c403a").get_luminance()
			and bottom_edge != null
			and bottom_edge.color.is_equal_approx(Color("c29969")),
			"Header is darker than enemy card backs and keeps its antique-gold lower border"
		)

	var original_window_size: Vector2i = root.size
	for target_size: Vector2i in [Vector2i(540, 960), Vector2i(405, 720), Vector2i(405, 900), Vector2i(1280, 839)]:
		root.size = target_size
		await process_frame
		duel.call("_layout_duel")
		await process_frame
		var opponent_hand: HBoxContainer = duel.get_node("DuelCanvas/OpponentHand") as HBoxContainer
		var canvas: Control = duel.get_node("DuelCanvas") as Control
		var header_gap: float = opponent_hand.position.y - (top_wash.position.y + top_wash.size.y)
		_check(
			header_gap >= 12.0 and header_gap <= 18.0,
			"Header keeps a 12–18 pixel breathing gap at %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			is_equal_approx(top_wash.position.x, 0.0)
			and is_equal_approx(top_wash.size.x, canvas.size.x),
			"Header spans the duel canvas width at %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			is_equal_approx(top_bar.position.x, opponent_hand.position.x)
			and is_equal_approx(top_bar.size.x, opponent_hand.size.x),
			"Header content aligns with hand margins at %dx%d" % [target_size.x, target_size.y]
		)
	root.size = original_window_size
	await process_frame
	duel.call("_layout_duel")
	await process_frame


func _check_card_edge_labels(duel: Node) -> void:
	var first_card := _first_card(duel.get_node("DuelCanvas/PlayerHand"))
	var top_label := first_card.find_child("TopPower", true, false) as Label
	var right_label := first_card.find_child("RightPower", true, false) as Label
	var bottom_label := first_card.find_child("BottomPower", true, false) as Label
	var left_label := first_card.find_child("LeftPower", true, false) as Label
	var card_rect: Rect2 = first_card.get_global_rect()
	var card_center: Vector2 = card_rect.get_center()
	_check(absf(top_label.get_global_rect().get_center().x - card_center.x) < 1.0 and top_label.get_global_rect().get_center().y < card_center.y, "Top power has its own rectangle centered on the top edge")
	_check(right_label.get_global_rect().get_center().x > card_center.x and absf(right_label.get_global_rect().get_center().y - card_center.y) < 1.0, "Right power has its own rectangle centered on the right edge")
	_check(absf(bottom_label.get_global_rect().get_center().x - card_center.x) < 1.0 and bottom_label.get_global_rect().get_center().y > card_center.y, "Bottom power has its own rectangle centered on the bottom edge")
	_check(left_label.get_global_rect().get_center().x < card_center.x and absf(left_label.get_global_rect().get_center().y - card_center.y) < 1.0, "Left power has its own rectangle centered on the left edge")
	_check(not top_label.text.is_empty() and not right_label.text.is_empty() and not bottom_label.text.is_empty() and not left_label.text.is_empty(), "All four edge powers contain display text")


func _check_card_picture_layout() -> void:
	var card: Control = CARD_SCENE.instantiate()
	root.add_child(card)
	card.size = Vector2(96.0, 128.0)
	card.call("configure", {
		"picture": "res://pics/LKT010_001.png",
		"powers": [1, 2, 3, 4],
		"ki": 0,
		"active_abilities": [],
	}, Rules.PLAYER_OWNER, false)
	await process_frame
	var picture: TextureRect = card.get_node("Overlay/CardPicture") as TextureRect
	_check(picture.visible and picture.texture != null, "A face-up catalog picture loads into the card view")
	_check(picture.size.is_equal_approx(Vector2(76.8, 76.8)), "A 96x128 card gives its picture 80% of the shorter side")
	_check(picture.position.is_equal_approx(Vector2(9.6, 25.6)), "The square picture is centered on both card axes")
	_check(picture.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "Picture dimensions never enlarge the card")
	_check(picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Picture keeps its source aspect ratio without cropping")
	for power_name: String in ["TopPower", "RightPower", "BottomPower", "LeftPower"]:
		var power_label: Label = card.get_node("Overlay/%s" % power_name) as Label
		_check(power_label.z_index > picture.z_index, "%s renders above the card picture" % power_name)

	card.size = Vector2(80.0, 120.0)
	await process_frame
	_check(picture.size.is_equal_approx(Vector2(64.0, 64.0)), "Picture recomputes its 80% square after a card resize")
	_check(picture.position.is_equal_approx(Vector2(8.0, 28.0)), "Resized picture remains exactly centered")
	card.call("set_face_down", true)
	_check(not picture.visible and (card.get_node("Overlay/ArtPlaceholder") as Label).text == "◆", "Face-down cards hide pictures and retain the existing card back")
	card.call("set_face_down", false)
	_check(picture.visible and picture.texture != null, "Revealing restores the same face picture")
	card.queue_free()
	await process_frame

	var blank_fixture: Control = CARD_SCENE.instantiate()
	root.add_child(blank_fixture)
	blank_fixture.call("configure", {
		"powers": [1, 1, 1, 1],
		"ki": 0,
		"active_abilities": [],
	}, Rules.PLAYER_OWNER, false)
	await process_frame
	var blank_picture: TextureRect = blank_fixture.get_node("Overlay/CardPicture") as TextureRect
	_check(not blank_picture.visible and blank_picture.texture == null, "Picture-less test fixtures remain valid blank-faced cards")
	blank_fixture.queue_free()
	await process_frame


func _check_hand_slots(container: Node) -> void:
	var has_five_slots: bool = container.get_child_count() == 5
	for child: Node in container.get_children():
		has_five_slots = has_five_slots and child.get_script() != CARD_SCRIPT and _count_cards(child) <= 1
	_check(has_five_slots, "%s keeps five persistent card slots" % container.name)


func _check_catalog_hands(duel: Node) -> void:
	var player_cards: Array[Control] = _cards_below(duel.get_node("DuelCanvas/PlayerHand"))
	var opponent_cards: Array[Control] = _cards_below(duel.get_node("DuelCanvas/OpponentHand"))
	var player_ids: Array[StringName] = []
	var opponent_ids: Array[StringName] = []
	for card: Control in player_cards:
		var player_card_data: Dictionary = card.get("card_data")
		player_ids.append(StringName(player_card_data.get("card_id", &"")))
	for card: Control in opponent_cards:
		var opponent_card_data: Dictionary = card.get("card_data")
		opponent_ids.append(StringName(opponent_card_data.get("card_id", &"")))
	_check(player_ids == Decks.get_player_card_ids(TEST_PROFILE_PATH), "Player hand resolves in saved deck order")
	_check(opponent_ids == [&"CangSongYingKe1", &"fire_envoy", &"tiger_general", &"TuNaShu1", &"TuNaShu1"], "Opponent hand resolves in catalog deck order")
	var gate_card_data: Dictionary = player_cards[1].get("card_data")
	var tiger_card_data: Dictionary = opponent_cards[2].get("card_data")
	var gate_abilities: Array = gate_card_data.get("active_abilities", [])
	var tiger_abilities: Array = tiger_card_data.get("active_abilities", [])
	_check(gate_abilities.size() == 1 and bool((gate_abilities[0] as Dictionary).get("retained_on_flip", false)), "Gate General view receives its retained catalog ability")
	_check(tiger_abilities.size() == 1 and bool((tiger_abilities[0] as Dictionary).get("retained_on_flip", false)), "Tiger General view receives its retained catalog ability")
	_check(not duel.has_method("_get_player_cards") and not duel.has_method("_get_opponent_cards"), "Controller no longer owns hard-coded card definitions")


func _check_side_deck_setup(duel: Node) -> void:
	var expected_by_owner: Dictionary = {
		Rules.PLAYER_OWNER: Decks.get_side_deck_card_ids(
			Decks.get_player_card_ids(TEST_PROFILE_PATH)
		),
		Rules.OPPONENT_OWNER: Decks.get_side_deck_card_ids(
			Decks.get_opponent_card_ids()
		),
	}
	var expected_instance_count: int = 10
	for owner_id: int in [Rules.PLAYER_OWNER, Rules.OPPONENT_OWNER]:
		var expected_ids: Array[StringName] = (
			expected_by_owner[owner_id] as Array[StringName]
		).duplicate()
		expected_ids.sort()
		var observed_ids: Array[StringName] = duel.debug_get_side_deck_card_ids(owner_id)
		observed_ids.sort()
		_check(observed_ids == expected_ids, "Owner %d side deck matches its main deck" % owner_id)
		expected_instance_count += expected_ids.size()
	var all_instance_ids: Array[StringName] = duel.debug_get_all_instance_ids()
	var unique_instance_ids: Dictionary = {}
	for instance_id: StringName in all_instance_ids:
		unique_instance_ids[instance_id] = true
	_check(
		all_instance_ids.size() == expected_instance_count
		and unique_instance_ids.size() == expected_instance_count,
		"Main and side decks use unique runtime instance IDs"
	)


func _expected_total_card_count() -> int:
	return (
		10
		+ Decks.get_side_deck_card_ids(
			Decks.get_player_card_ids(TEST_PROFILE_PATH)
		).size()
		+ Decks.get_side_deck_card_ids(Decks.get_opponent_card_ids()).size()
	)


func _check_duplicate_enemy_instances() -> void:
	var duplicate_duel: Node = _instantiate_duel()
	var duplicate_card_ids: Array[StringName] = [
		&"fire_envoy",
		&"fire_envoy",
		&"fire_envoy",
		&"fire_envoy",
		&"fire_envoy",
	]
	duplicate_duel.set("opponent_card_ids", duplicate_card_ids)
	root.add_child(duplicate_duel)
	await process_frame
	await process_frame
	var instance_ids: Array[StringName] = duplicate_duel.debug_get_hand_instance_ids(
		Rules.OPPONENT_OWNER
	)
	var unique_ids: Dictionary = {}
	for instance_id: StringName in instance_ids:
		unique_ids[instance_id] = true
	_check(
		instance_ids.size() == 5 and unique_ids.size() == 5,
		"Exact duplicate enemy cards receive distinct runtime instance IDs"
	)
	var observed_side_ids: Array[StringName] = duplicate_duel.debug_get_side_deck_card_ids(
		Rules.OPPONENT_OWNER
	)
	var expected_side_ids: Array[StringName] = Decks.get_side_deck_card_ids(
		duplicate_card_ids
	)
	observed_side_ids.sort()
	expected_side_ids.sort()
	_check(
		observed_side_ids == expected_side_ids,
		"Exact duplicate enemy main cards do not multiply side-deck entries"
	)
	duplicate_duel.queue_free()
	await process_frame


func _check_player_draw_and_instance_mapping() -> void:
	var draw_duel: Node = _instantiate_duel()
	draw_duel.set("testing_mode", true)
	draw_duel.set("side_deck_shuffle_seed", 4102)
	root.add_child(draw_duel)
	await process_frame
	await process_frame
	draw_duel.debug_set_fast_mode(true)
	_check(not draw_duel.has_node("DrawAudio"), "Ink Summon has no dedicated draw audio")
	var initial_card: Control = _first_card(draw_duel.get_node("DuelCanvas/PlayerHand"))
	_check(initial_card.has_node("Overlay/InkBloom") and initial_card.has_method("play_draw_summon"), "Card view exposes the reusable Ink Summon presentation")
	var ink_bloom: Control = initial_card.get_node("Overlay/InkBloom") as Control
	var ink_script: Script = ink_bloom.get_script()
	_check(not ink_bloom is Label and ink_script != null and ink_script.resource_path == "res://scripts/ink_bloom.gd", "Ink Summon uses a custom drawing control instead of a text glyph")
	_check(ink_bloom.has_method("set_ink_color") and ink_bloom.has_method("get_pool_count") and ink_bloom.has_method("get_droplet_count"), "Ink bloom exposes reusable color and geometry controls")
	if ink_bloom.has_method("get_pool_count") and ink_bloom.has_method("get_droplet_count"):
		_check(int(ink_bloom.call("get_pool_count")) >= 3 and int(ink_bloom.call("get_droplet_count")) >= 3, "Ink bloom contains overlapping pools and detached droplets")

	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 1, 0, false), "Draw fixture places the first player card")
	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 8, false), "Draw fixture places the first opponent card")
	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 1, 6, false), "Draw fixture places the second player card")
	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 1, false), "Draw fixture places a future flip target")
	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 2, 4, false), "Playing Fa Zheng from a three-card hand commits")

	var logical_ids: Array[StringName] = draw_duel.debug_get_hand_instance_ids(Rules.PLAYER_OWNER)
	var visual_ids: Array[StringName] = draw_duel.debug_get_hand_view_instance_ids(Rules.PLAYER_OWNER)
	var trace: Array[StringName] = draw_duel.debug_get_presentation_trace()
	_check(logical_ids.size() == 4 and visual_ids.size() == 4, "Fa Zheng draws two cards without exceeding five")
	_check(logical_ids != visual_ids, "Drawn cards fill earlier empty slots without repacking logical hand order")
	_check(
		trace.size() >= 2
		and trace.slice(trace.size() - 2)
		== [
			&"card_drawn",
			&"card_drawn",
		],
		"Sequential Ink Summons resolve in order"
	)
	_check(_count_face_down(_cards_below(draw_duel.get_node("DuelCanvas/PlayerHand"))) == 0, "Testing-mode player draws remain face-up")
	_check_hand_slots(draw_duel.get_node("DuelCanvas/PlayerHand"))

	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 3, false), "Draw fixture advances through the opponent turn")
	logical_ids = draw_duel.debug_get_hand_instance_ids(Rules.PLAYER_OWNER)
	var intended_instance_id: StringName = logical_ids[2]
	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 2, 2, false), "A drawn card commits by logical hand index")
	_check(draw_duel.debug_get_board_card_instance_id(2) == intended_instance_id, "Instance-ID mapping places the intended drawn card despite visual-order divergence")
	draw_duel.queue_free()
	await process_frame


func _check_opponent_draw_visibility() -> void:
	var draw_duel: Node = _instantiate_duel()
	draw_duel.set("side_deck_shuffle_seed", 991)
	root.add_child(draw_duel)
	await process_frame
	await process_frame
	draw_duel.debug_set_fast_mode(true)

	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 0, false), "Opponent-draw fixture places player card one")
	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 8, false), "Opponent-draw fixture places opponent card one")
	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 2, false), "Opponent-draw fixture places player card two")
	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 6, false), "Opponent-draw fixture places opponent card two")
	_check(await draw_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 1, false), "Opponent-draw fixture advances to TuNaShu1")
	_check(await draw_duel.debug_commit_move(Rules.OPPONENT_OWNER, 1, 7, false), "Playing TuNaShu1 from a three-card hand commits")

	var opponent_views: Array[Control] = _cards_below(draw_duel.get_node("DuelCanvas/OpponentHand"))
	var trace: Array[StringName] = draw_duel.debug_get_presentation_trace()
	_check(opponent_views.size() == 3, "TuNaShu1 draws one card into the opponent hand")
	_check(_count_face_down(opponent_views) == opponent_views.size(), "Normal-mode opponent draws remain fully concealed")
	_check(not trace.is_empty() and trace.back() == &"card_drawn", "Opponent Ink Summon resolves after TuNaShu1 is played")
	_check(not draw_duel.has_node("DrawAudio"), "Opponent Ink Summon remains silent in fast and normal presentation")
	_check_hand_slots(draw_duel.get_node("DuelCanvas/OpponentHand"))
	draw_duel.queue_free()
	await process_frame


func _check_normal_opponent_concealment(duel: Node) -> void:
	var opponent_cards: Array[Control] = _cards_below(duel.get_node("DuelCanvas/OpponentHand"))
	var all_concealed: bool = not opponent_cards.is_empty()
	var all_private_data_retained: bool = true
	for card: Control in opponent_cards:
		var card_data: Dictionary = card.get("card_data")
		all_private_data_retained = (
			all_private_data_retained
			and not card_data.has("name")
			and not String(card_data.get("glyph", "")).is_empty()
			and not String(card_data.get("picture", "")).is_empty()
			and typeof(card_data.get("description", null)) == TYPE_STRING
			and (card_data.get("powers", []) as Array).size() == 4
		)
		all_concealed = (
			all_concealed
			and card.has_method("is_face_down")
			and bool(card.call("is_face_down"))
			and not (card.get_node("Overlay/TopPower") as Label).visible
			and not (card.get_node("Overlay/RightPower") as Label).visible
			and not (card.get_node("Overlay/BottomPower") as Label).visible
			and not (card.get_node("Overlay/LeftPower") as Label).visible
			and not (card.get_node("Overlay/CardPicture") as TextureRect).visible
			and card.tooltip_text.is_empty()
		)
	_check(all_concealed, "Normal mode presents every remaining opponent card face-down without power or tooltip leaks")
	_check(all_private_data_retained, "Face-down opponent views retain complete private card data")

	var first_card: Control = opponent_cards[0]
	var first_data: Dictionary = first_card.get("card_data")
	var supports_visibility: bool = first_card.has_method("set_face_down") and first_card.has_method("is_face_down")
	_check(supports_visibility, "Card view exposes reusable face-down presentation controls")
	if supports_visibility:
		first_card.call("set_face_down", false)
		first_card.call("set_face_down", false)
		var powers: Array = first_data.get("powers", [])
		_check(not bool(first_card.call("is_face_down")), "Repeated reveal calls leave the card face-up")
		var revealed_picture: TextureRect = first_card.get_node("Overlay/CardPicture") as TextureRect
		_check(revealed_picture.visible and revealed_picture.texture != null and revealed_picture.texture.resource_path == String(first_data.get("picture", "")), "Revealing restores the opponent picture from retained data")
		_check((first_card.get_node("Overlay/ArtPlaceholder") as Label).text.is_empty(), "Face-up cards keep the disabled glyph display empty")
		_check((first_card.get_node("Overlay/TopPower") as Label).visible and (first_card.get_node("Overlay/TopPower") as Label).text == str(powers[0]), "Revealing restores visible power labels from retained data")
		_check(first_card.tooltip_text.is_empty(), "Revealing keeps the disabled card tooltip empty")
		first_card.call("set_face_down", true)
		first_card.call("set_face_down", true)
		_check(bool(first_card.call("is_face_down")) and not revealed_picture.visible and (first_card.get_node("Overlay/ArtPlaceholder") as Label).text == "◆" and first_card.tooltip_text.is_empty(), "Repeated conceal calls remain idempotent and restore the card back")


func _check_card_inspector_modal() -> void:
	var inspect_duel: Node = _instantiate_duel()
	root.add_child(inspect_duel)
	await process_frame
	await process_frame
	inspect_duel.debug_set_fast_mode(true)
	var inspector: Control = inspect_duel.get_node("DuelCanvas/CardInspector") as Control
	var board_grid: GridContainer = inspect_duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as GridContainer
	var score_overlay: VBoxContainer = inspect_duel.get_node("DuelCanvas/ScoreOverlay") as VBoxContainer
	var player_card: Control = _first_card(inspect_duel.get_node("DuelCanvas/PlayerHand"))
	var opponent_card: Control = _first_card(inspect_duel.get_node("DuelCanvas/OpponentHand"))
	var occupancy_before: int = inspect_duel.debug_get_board_occupancy()
	var turn_count_before: int = inspect_duel.debug_get_simulation_turn_count()

	_submit_card_tap(player_card)
	await process_frame
	_check(inspect_duel.debug_is_inspection_open() and inspector.visible, "Tapping a revealed hand card opens the production inspector")
	_check(not board_grid.visible and not score_overlay.visible, "Inspector replaces the board and score presentation")
	_check(
		(inspector.get_node("Parchment/Body/Margin/Scroll/Content/Title") as Label).text == "苍松迎客",
		"Inspector uses glyph as the visible card name"
	)
	var tags: HBoxContainer = inspector.get_node("Parchment/Body/Margin/Scroll/Content/Tags") as HBoxContainer
	_check(
		(tags.get_node("SectTag/Value") as Label).text == "华山派"
		and (tags.get_node("TierTag/Value") as Label).text == "不凡"
		and (tags.get_node("WeaponTag/Value") as Label).text == "剑法",
		"Production inspector displays sect, tier, and weapon in order"
	)
	var blocked_move: bool = await inspect_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false)
	_check(
		not blocked_move
		and inspect_duel.debug_get_board_occupancy() == occupancy_before
		and inspect_duel.debug_get_simulation_turn_count() == turn_count_before,
		"Inspector blocks duel actions without changing logical state"
	)
	var parchment: Control = inspector.get_node("Parchment") as Control
	_check(
		parchment.position.is_equal_approx(board_grid.position)
		and parchment.size.is_equal_approx(board_grid.size),
		"Inspector parchment exactly tracks the responsive board rectangle"
	)
	inspect_duel.debug_close_inspection()
	await process_frame
	_check(not inspect_duel.debug_is_inspection_open() and board_grid.visible and score_overlay.visible, "Closing restores board and score presentation")
	_check(_count_playable(_cards_below(inspect_duel.get_node("DuelCanvas/PlayerHand"))) == _count_cards(inspect_duel.get_node("DuelCanvas/PlayerHand")), "Closing restores player hand interaction")

	_submit_card_tap(opponent_card)
	await process_frame
	_check(not inspect_duel.debug_is_inspection_open(), "Tapping a face-down opponent card reveals nothing")

	var placeholder_opened: bool = inspect_duel.debug_open_inspection({
		"glyph": "",
		"sect": "",
		"tier": null,
		"weapon": "",
		"description": "",
		"flavor": "",
	})
	_check(placeholder_opened, "Controller accepts an explicit revealed-card inspection fixture")
	var content: VBoxContainer = inspector.get_node("Parchment/Body/Margin/Scroll/Content") as VBoxContainer
	_check(
		(content.get_node("Title") as Label).text == "—"
		and (content.get_node("Description") as Label).text == "—"
		and (content.get_node("Flavor") as Label).text == "—",
		"Production inspector keeps placeholders for incomplete card information"
	)
	inspect_duel.debug_close_inspection()
	inspect_duel.debug_close_inspection()
	await process_frame
	_check(not inspect_duel.debug_is_inspection_open() and board_grid.visible, "Repeated production close requests remain idempotent")

	inspect_duel.set("turn_state", 1)
	var resolving_opened: bool = inspect_duel.debug_open_inspection(player_card.get("card_data"))
	_check(not resolving_opened, "Inspection requests are rejected during resolution")
	inspect_duel.set("turn_state", 0)
	inspect_duel.queue_free()
	await process_frame


func _submit_card_tap(card: Control) -> void:
	var center: Vector2 = card.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	card.call("_gui_input", press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	card.call("_gui_input", release)


func _check_inspector_holds_completed_ai_move() -> void:
	var ai_duel: Node = _instantiate_duel()
	root.add_child(ai_duel)
	await process_frame
	await process_frame
	ai_duel.debug_set_fast_mode(true)
	ai_duel.debug_set_search_limits(0.75, {"max_depth": 99})
	ai_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, true)
	var search_started: bool = ai_duel.debug_is_search_running()
	var inspect_card: Control = _first_card(ai_duel.get_node("DuelCanvas/PlayerHand"))
	var inspector_opened: bool = (
		inspect_card != null
		and ai_duel.debug_open_inspection(inspect_card.get("card_data"))
	)
	_check(search_started and inspector_opened, "Inspector can open while the opponent search is running")

	var frames_waited: int = 0
	while ai_duel.debug_is_search_running() and frames_waited < 600:
		await process_frame
		frames_waited += 1
	_check(not ai_duel.debug_is_search_running(), "Opponent search continues and finishes behind the inspector")
	_check(
		ai_duel.debug_is_inspection_open()
		and ai_duel.debug_get_board_occupancy() == 1,
		"Completed opponent result remains unapplied while inspection is open"
	)

	ai_duel.debug_close_inspection()
	frames_waited = 0
	while ai_duel.debug_get_board_occupancy() < 2 and frames_waited < 300:
		await process_frame
		frames_waited += 1
	_check(ai_duel.debug_get_board_occupancy() >= 2, "Opponent result applies after inspection closes")
	_check(ai_duel.debug_get_active_owner() == Rules.PLAYER_OWNER, "Opponent result returns control to the player")
	for _settle_frame: int in range(10):
		await process_frame
	ai_duel.queue_free()
	for _free_frame: int in range(3):
		await process_frame


func _check_focus_loss_return() -> void:
	var focus_duel: Node = _instantiate_duel()
	root.add_child(focus_duel)
	await process_frame
	await process_frame
	focus_duel.debug_set_fast_mode(true)
	var card: Control = _first_card(focus_duel.get_node("DuelCanvas/PlayerHand"))
	var home_parent: Node = card.get_parent()
	card.call("_try_begin_drag", card.get_global_rect().get_center(), -1)
	_check(card.get_parent() == focus_duel.get_node("DuelCanvas/DragLayer"), "A playable card enters the drag layer when dragging starts")
	card.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(card.get_parent() == focus_duel.get_node("DuelCanvas/DragLayer"), "Focus-loss handling defers scene-tree mutation until notification processing ends")
	await process_frame
	await process_frame
	_check(card.get_parent() == home_parent, "A focus-loss drag cancellation safely returns the card to its slot")
	focus_duel.queue_free()
	await process_frame


func _check_dragged_card_commits_through_simulator() -> void:
	var drag_duel: Node = _instantiate_duel()
	drag_duel.set("opponent_card_ids", [
		&"TaiShan18Pan1",
		&"WuDaFuJian1",
		&"QiXinLuoChangKong2",
		&"TianChangZhang3",
		&"HenShanJianZhen2",
	])
	root.add_child(drag_duel)
	await process_frame
	await process_frame
	drag_duel.debug_set_fast_mode(true)
	var card: Control = _first_card(drag_duel.get_node("DuelCanvas/PlayerHand"))
	drag_duel._on_card_drag_started(card, card.get_global_rect().get_center())
	_check(card.get_parent() == drag_duel.get_node("DuelCanvas/DragLayer"), "Real drag path reparents the card before commit")
	await drag_duel._commit_card(card, 0, 1)
	_check(drag_duel.debug_get_simulation_turn_count() == 2, "Real dragged placement advances simulator state for both turns")
	var opponent_board_card: Control = null
	for board_card_value: Variant in drag_duel.get("board_cards"):
		if board_card_value is Control and int((board_card_value as Control).get("owner_id")) == 2:
			opponent_board_card = board_card_value as Control
			break
	_check(opponent_board_card != null, "Normal AI places an opponent card view on the board")
	if opponent_board_card != null:
		_check(opponent_board_card.has_method("is_face_down") and not bool(opponent_board_card.call("is_face_down")), "An AI-played opponent card reveals when it reaches the board")
	drag_duel.queue_free()
	await process_frame


func _check_aspect_ratio_input_paths() -> void:
	var original_window_size: Vector2i = root.size
	for target_size: Vector2i in [Vector2i(405, 900), Vector2i(1280, 839)]:
		root.size = target_size
		await process_frame
		var aspect_duel: Node = _instantiate_duel()
		aspect_duel.set("testing_mode", true)
		root.add_child(aspect_duel)
		await process_frame
		await process_frame
		aspect_duel.debug_set_fast_mode(true)
		aspect_duel.call("_layout_duel")
		await process_frame

		var canvas: Control = aspect_duel.get_node("DuelCanvas") as Control
		var board_grid: GridContainer = aspect_duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as GridContainer
		var replay_button: Button = aspect_duel.get_node("DuelCanvas/ReplayButton") as Button
		_check(
			replay_button.get_global_rect().end.x <= board_grid.get_global_rect().position.x,
			"Replay icon stays left of the board on %dx%d" % [target_size.x, target_size.y]
		)
		_check(
			absf(
				replay_button.get_global_rect().get_center().y
				- board_grid.get_global_rect().get_center().y
			) < 1.0,
			"Replay icon stays vertically centered on %dx%d" % [target_size.x, target_size.y]
		)
		var card: Control = _first_card(aspect_duel.get_node("DuelCanvas/PlayerHand"))
		var target_cell: Control = board_grid.get_child(0) as Control
		var target_position: Vector2 = target_cell.get_global_rect().get_center()
		var card_center: Vector2 = card.get_global_rect().get_center()
		card.call("_try_begin_drag", card_center, -1)
		card.call("_move_drag", target_position)
		card.call("_try_end_drag", target_position, -1)

		var frames_waited: int = 0
		while aspect_duel.debug_get_board_occupancy() < 1 and frames_waited < 60:
			await process_frame
			frames_waited += 1
		_check(
			aspect_duel.debug_get_board_occupancy() == 1,
			"Global drag commits to the intended board on %dx%d" % [target_size.x, target_size.y]
		)

		var extension_point: Vector2
		if target_size.y > int(round(float(target_size.x) / (9.0 / 16.0))):
			extension_point = Vector2(canvas.get_global_rect().get_center().x, canvas.global_position.y * 0.5)
		else:
			extension_point = Vector2(canvas.global_position.x * 0.5, canvas.get_global_rect().get_center().y)
		_check(
			int(aspect_duel.call("_get_cell_at_position", extension_point)) == -1,
			"Decorative extension is never a board target on %dx%d" % [target_size.x, target_size.y]
		)

		if target_size == Vector2i(405, 900):
			var inspect_card: Control = _first_card(aspect_duel.get_node("DuelCanvas/PlayerHand"))
			var opened: bool = aspect_duel.debug_open_inspection(inspect_card.get("card_data"))
			var inspector: Control = aspect_duel.get_node("DuelCanvas/CardInspector") as Control
			_check(opened, "Tall-screen fixture opens the inspector")
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = extension_point
			inspector.call("_input", press)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = extension_point
			inspector.call("_input", release)
			await process_frame
			_check(
				not aspect_duel.debug_is_inspection_open(),
				"Tap-to-close inspection still accepts a decorative-extension tap"
			)

		aspect_duel.queue_free()
		await process_frame
	root.size = original_window_size
	await process_frame


func _check_testing_mode_manual_turns() -> void:
	var test_duel: Node = _instantiate_duel()
	test_duel.set("testing_mode", true)
	root.add_child(test_duel)
	await process_frame
	await process_frame
	test_duel.debug_set_fast_mode(true)

	var player_cards: Array[Control] = _cards_below(test_duel.get_node("DuelCanvas/PlayerHand"))
	var opponent_cards: Array[Control] = _cards_below(test_duel.get_node("DuelCanvas/OpponentHand"))
	var all_face_up: bool = true
	for card: Control in player_cards + opponent_cards:
		all_face_up = all_face_up and card.has_method("is_face_down") and not bool(card.call("is_face_down"))
	_check(all_face_up, "Testing mode starts with both hands face-up")
	_check(_count_playable(player_cards) == player_cards.size() and _count_playable(opponent_cards) == 0, "Testing mode initially enables only the player hand")
	_check("Testing" in (test_duel.get_node("DuelCanvas/TurnStatus") as Label).text and "Player" in (test_duel.get_node("DuelCanvas/TurnStatus") as Label).text, "Testing status identifies the opening player side")

	var player_card: Control = player_cards[0]
	test_duel._on_card_drag_started(player_card, player_card.get_global_rect().get_center())
	_check(player_card.get_parent() == test_duel.get_node("DuelCanvas/DragLayer"), "Testing player drag uses the production drag layer")
	await test_duel._commit_card(player_card, 0, 1)
	_check(test_duel.debug_get_board_occupancy() == 1 and test_duel.debug_get_simulation_turn_count() == 1, "Testing mode suppresses the automatic AI reply")
	opponent_cards = _cards_below(test_duel.get_node("DuelCanvas/OpponentHand"))
	_check(_count_playable(_cards_below(test_duel.get_node("DuelCanvas/PlayerHand"))) == 0 and _count_playable(opponent_cards) == opponent_cards.size(), "Testing mode enables only the opponent hand on the opponent turn")
	_check("Testing" in (test_duel.get_node("DuelCanvas/TurnStatus") as Label).text and "Opponent" in (test_duel.get_node("DuelCanvas/TurnStatus") as Label).text, "Testing status identifies the opponent side")

	var opponent_card: Control = opponent_cards[0]
	var opponent_home: Node = opponent_card.get_parent()
	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	_check(opponent_card.get_parent() == test_duel.get_node("DuelCanvas/DragLayer"), "Testing opponent drag uses the production drag layer")
	opponent_card.call("_try_end_drag", Vector2(-100.0, -100.0), -1)
	await process_frame
	_check(opponent_card.get_parent() == opponent_home, "Invalid testing opponent drop returns to its original top-hand slot")

	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	opponent_card.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	_check(opponent_card.get_parent() == opponent_home, "Focus loss returns a testing opponent card to its original top-hand slot")

	opponent_card.call("_try_begin_drag", opponent_card.get_global_rect().get_center(), -1)
	_check(opponent_card.get_parent() == test_duel.get_node("DuelCanvas/DragLayer"), "Testing opponent card can begin a second valid drag")
	await test_duel._commit_card(opponent_card, 1, 2)
	_check(test_duel.debug_get_board_occupancy() == 2 and test_duel.debug_get_simulation_turn_count() == 2, "Manual opponent placement advances the production simulator path exactly once")
	_check(_count_playable(_cards_below(test_duel.get_node("DuelCanvas/PlayerHand"))) == _count_cards(test_duel.get_node("DuelCanvas/PlayerHand")) and _count_playable(_cards_below(test_duel.get_node("DuelCanvas/OpponentHand"))) == 0, "Testing control returns to the player hand after the opponent move")
	_check(not test_duel.debug_is_search_running() and test_duel.debug_get_last_search_report().is_empty(), "Testing mode never starts an opponent search session")
	test_duel.queue_free()
	await process_frame


func _check_manual_activate_move() -> void:
	var duel: Node = _instantiate_duel()
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	var placed_youfen: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 3, 4, false)
	_check(placed_youfen, "有凤来仪 can enter the board through the production action path")
	var youfen_instance: StringName = duel.debug_get_board_card_instance_id(4)
	var opponent_played: bool = await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 0, false)
	_check(opponent_played, "Opponent action returns priority for activate testing")
	var pulses_before_activation: Array[StringName] = duel.debug_get_ability_pulse_trace()
	var activated: bool = await duel.debug_commit_activate(Rules.PLAYER_OWNER, 4, 5, false)
	_check(activated, "Production controller accepts a legal board activation")
	_check(not duel.debug_has_board_card_view(4) and duel.debug_has_board_card_view(5), "Controller moves the board view to the target cell")
	_check(duel.debug_get_board_card_instance_id(5) == youfen_instance, "Controller preserves the moving card view identity")
	var moved_card: CardView = (duel.get("board_cards") as Array)[5] as CardView
	var ki_badge := moved_card.get_node("Overlay/KiBadge") as PanelContainer
	var ki_value := moved_card.get_node("Overlay/KiBadge/Value") as Control
	_check(int(moved_card.card_data.get("ki", -1)) == 0, "Controller synchronizes spent ki into the card view")
	_check(ki_badge.visible and String(ki_value.get("text")) == "0", "Zero-ki card with an activate ability keeps its dimmed badge")
	var trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(trace.has(&"ability_activated") and trace.has(&"ki_changed") and trace.has(&"card_moved"), "Controller presents the canonical activation events")
	_check(
		duel.debug_get_ability_pulse_trace() == pulses_before_activation,
		"Activate ability presentation adds no passive card pulse"
	)
	duel.queue_free()
	await process_frame


func _check_meng_huo_extra_turn_presentation() -> void:
	var duel: Node = _instantiate_duel()
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	var extra_turn_vfx: Control = duel.get_node_or_null("DuelCanvas/ExtraTurnVfx") as Control
	_check(extra_turn_vfx != null, "Duel scene contains the reusable extra-turn VFX overlay")
	if extra_turn_vfx != null:
		_check(extra_turn_vfx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Extra-turn VFX never intercepts input")
		_check(
			extra_turn_vfx.has_method("play_convergence")
			and extra_turn_vfx.has_method("debug_get_last_bead_count")
			and extra_turn_vfx.has_method("debug_get_pulse_count")
			and extra_turn_vfx.has_method("debug_is_clean"),
			"Extra-turn overlay exposes reusable playback and cleanup diagnostics"
		)
	var player_opened: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 8, false)
	var opponent_targeted: bool = await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 5, false)
	var meng_played: bool = await duel.debug_commit_move(Rules.PLAYER_OWNER, 1, 4, false)
	_check(player_opened and opponent_targeted and meng_played, "Meng Huo presentation fixture uses three production actions")
	_check(duel.debug_get_active_owner() == Rules.PLAYER_OWNER, "Meng Huo's extra turn returns control to the same player")
	_check(duel.debug_get_simulation_turn_count() == 3, "Extra-turn grant does not add a simulation turn by itself")
	var meng_view: CardView = (duel.get("board_cards") as Array)[4] as CardView
	_check(meng_view != null and StringName(meng_view.card_data.get("card_id", &"")) == &"meng_huo", "Meng Huo remains mapped to his production board view")
	var ki_badge := meng_view.get_node("Overlay/KiBadge") as PanelContainer
	var ki_value := meng_view.get_node("Overlay/KiBadge/Value") as Control
	_check(
		int(meng_view.card_data.get("ki", -1)) == 0
		and ki_badge.visible
		and ki_value.visible
		and String(ki_value.get("text")) == "0",
		"Meng Huo's ki-gated passive trigger shows zero on a light bead at zero ki"
	)
	var meng_instance_id := StringName(meng_view.card_data.get("instance_id", &""))
	_check(
		duel.debug_get_ability_pulse_trace().count(meng_instance_id) == 1,
		"Meng Huo's consecutive gain and end-turn triggers produce one generic card pulse"
	)
	var ki_trace: Array[int] = duel.debug_get_ki_presentation_trace()
	_check(ki_trace.slice(ki_trace.size() - 2) == [1, 0], "Controller presents gained ki before the end-turn drain")
	var presentation_trace: Array[StringName] = duel.debug_get_presentation_trace()
	_check(
		presentation_trace.has(&"attack_started")
		and presentation_trace.has(&"card_flipped")
		and presentation_trace.has(&"extra_turn_granted"),
		"Attack, capture, and extra-turn feedback use the ordered event presenter"
	)
	if extra_turn_vfx != null and extra_turn_vfx.has_method("debug_get_last_bead_count"):
		_check(int(extra_turn_vfx.call("debug_get_last_bead_count")) == 1, "One granting Meng Huo produces one convergence bead")
		_check(int(extra_turn_vfx.call("debug_get_pulse_count")) == 1, "One granted extra turn produces one board pulse")
		_check(bool(extra_turn_vfx.call("debug_is_clean")), "Fast-mode extra-turn playback leaves no temporary visuals")
		var board_cards: Array = duel.get("board_cards") as Array
		var second_source: CardView = board_cards[8] as CardView
		await extra_turn_vfx.call(
			"play_convergence",
			[meng_view, meng_view],
			(duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as Control).get_global_rect(),
			0.0,
			0.0,
			Color("e3b84f")
		)
		_check(int(extra_turn_vfx.call("debug_get_last_bead_count")) == 1, "Duplicate granting sources are deduplicated")
		await extra_turn_vfx.call(
			"play_convergence",
			[meng_view, second_source],
			(duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as Control).get_global_rect(),
			0.0,
			0.0,
			Color("e3b84f")
		)
		_check(int(extra_turn_vfx.call("debug_get_last_bead_count")) == 2, "Multiple valid sources produce concurrent convergence beads")
		var pulses_before_missing: int = int(extra_turn_vfx.call("debug_get_pulse_count"))
		await extra_turn_vfx.call(
			"play_convergence",
			[],
			(duel.get_node("DuelCanvas/BoardCenter/BoardGrid") as Control).get_global_rect(),
			0.0,
			0.0,
			Color("e3b84f")
		)
		_check(int(extra_turn_vfx.call("debug_get_pulse_count")) == pulses_before_missing + 1, "Missing source views still produce the board pulse")
		_check(bool(extra_turn_vfx.call("debug_is_clean")), "Repeated and source-less playback cleans up completely")
	_check((duel.get_node("DuelCanvas/TurnStatus") as Label).text == "你的回合 · 拖动卡牌", "Normal player status returns after extra-turn feedback")
	_check(_count_playable(_cards_below(duel.get_node("DuelCanvas/PlayerHand"))) == _count_cards(duel.get_node("DuelCanvas/PlayerHand")), "Player hand is enabled for the granted extra turn")
	_check(_count_playable(_cards_below(duel.get_node("DuelCanvas/OpponentHand"))) == 0, "Opponent hand remains disabled during the player's extra turn")
	duel.queue_free()
	await process_frame


func _check_player_gate_exile() -> void:
	var exile_duel: Node = _instantiate_duel()
	root.add_child(exile_duel)
	await process_frame
	await process_frame
	exile_duel.debug_set_fast_mode(true)
	_check(exile_duel.has_node("RemovalAudio"), "Duel scene contains dedicated removal audio")
	var gate_view: Control = _cards_below(exile_duel.get_node("DuelCanvas/PlayerHand"))[1]
	_check(gate_view.has_node("Overlay/InkSlash"), "Card view contains the exile ink overlay")
	_check(gate_view.has_method("play_effect_pulse") and gate_view.has_method("play_exile"), "Card view exposes exile presentation methods")

	var first_placed: bool = await exile_duel.debug_commit_move(1, 0, 0, false)
	var target_placed: bool = await exile_duel.debug_commit_move(2, 1, 5, false)
	var gate_placed: bool = await exile_duel.debug_commit_move(1, 0, 4, false)
	_check(first_placed and target_placed and gate_placed, "Scripted Gate General exile uses production move commits")
	await process_frame
	_check(exile_duel.debug_get_board_occupancy() == 2, "Gate General removes Fire Envoy instead of flipping it")
	_check(exile_duel.has_method("debug_has_board_card_view") and not bool(exile_duel.call("debug_has_board_card_view", 5)), "Gate General exile clears the target card view")
	_check(exile_duel.has_method("debug_get_removed_count") and int(exile_duel.call("debug_get_removed_count", 2)) == 1, "Fire Envoy enters the opponent's removed zone")
	_check(exile_duel.has_method("debug_can_place_at") and bool(exile_duel.call("debug_can_place_at", 5)), "Gate General's cleared cell is reusable")
	var gate_scores: Vector2i = exile_duel.debug_get_scores()
	_check(gate_scores == Vector2i(2, 0), "Gate General exile awards no point for the removed target")
	var gate_trace: Array[StringName] = exile_duel.debug_get_presentation_trace()
	_check(
		gate_trace.rfind(&"attack_started") < gate_trace.rfind(&"ability_triggered")
		and gate_trace.rfind(&"ability_triggered") < gate_trace.rfind(&"card_exiled"),
		"Gate interception presents attack cue, target pulse, then exile"
	)
	_check(
		exile_duel.debug_get_attack_vfx_trace().size() == 1,
		"Gate interception still plays one attempted-attack stroke"
	)
	exile_duel.queue_free()
	await process_frame


func _check_opponent_tiger_exile() -> void:
	var exile_duel: Node = _instantiate_duel()
	root.add_child(exile_duel)
	await process_frame
	await process_frame
	exile_duel.debug_set_fast_mode(true)
	var target_placed: bool = await exile_duel.debug_commit_move(1, 0, 4, false)
	var tiger_placed: bool = await exile_duel.debug_commit_move(2, 2, 5, false)
	_check(target_placed and tiger_placed, "Scripted Tiger General exile uses production move commits")
	await process_frame
	_check(exile_duel.debug_get_board_occupancy() == 1, "Tiger General removes Xu Shu instead of flipping it")
	_check(exile_duel.has_method("debug_has_board_card_view") and not bool(exile_duel.call("debug_has_board_card_view", 4)), "Tiger General exile clears the target card view")
	_check(exile_duel.has_method("debug_get_removed_count") and int(exile_duel.call("debug_get_removed_count", 1)) == 1, "Xu Shu enters the player's removed zone")
	_check(exile_duel.has_method("debug_can_place_at") and bool(exile_duel.call("debug_can_place_at", 4)), "Tiger General's cleared cell is reusable")
	var tiger_scores: Vector2i = exile_duel.debug_get_scores()
	_check(tiger_scores == Vector2i(0, 1), "Tiger General exile awards no point for the removed target")
	exile_duel.queue_free()
	await process_frame


func _check_cangsong_reaction_presentation() -> void:
	var flip_duel: Node = _instantiate_duel()
	root.add_child(flip_duel)
	await process_frame
	await process_frame
	flip_duel.debug_set_fast_mode(true)
	_check(await flip_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false), "Reaction fixture places CangSong")
	var opponent_fire_ids: Array[StringName] = flip_duel.debug_get_hand_instance_ids(Rules.OPPONENT_OWNER)
	var fire_instance_id: StringName = opponent_fire_ids[1]
	_check(await flip_duel.debug_commit_move(Rules.OPPONENT_OWNER, 1, 5, false), "Enemy card commits inside CangSong range")
	await process_frame
	var flipped_views: Array = flip_duel.get("board_cards")
	var flipped_view: Control = flipped_views[5] as Control
	_check(flipped_view != null and is_instance_valid(flipped_view), "Reaction flip keeps the summoned card view on board")
	_check(flip_duel.debug_get_board_card_instance_id(5) == fire_instance_id, "Reaction flip preserves summoned view identity")
	_check(int(flipped_view.get("owner_id")) == Rules.PLAYER_OWNER, "Reaction flip reconciles the summoned view to its new owner")
	_check(
		&"card_flipped" in flip_duel.debug_get_presentation_trace(),
		"Reaction flip uses the existing capture presentation"
	)
	var reaction_trace: Array[StringName] = flip_duel.debug_get_presentation_trace()
	_check(
		reaction_trace.rfind(&"ability_triggered")
		< reaction_trace.rfind(&"attack_started")
		and reaction_trace.rfind(&"attack_started")
		< reaction_trace.rfind(&"card_flipped"),
		"CangSong presents its pulse, attack stroke, then reaction flip"
	)
	_check(
		flip_duel.debug_get_attack_vfx_trace().size() == 1,
		"CangSong reaction plays one attack stroke"
	)
	var cang_instance_id: StringName = flip_duel.debug_get_board_card_instance_id(4)
	_check(
		flip_duel.debug_get_ability_pulse_trace().count(cang_instance_id) == 1,
		"CangSong's reaction produces one generic card pulse"
	)
	flip_duel.queue_free()
	await process_frame

	var exile_duel: Node = _instantiate_duel()
	root.add_child(exile_duel)
	await process_frame
	await process_frame
	exile_duel.debug_set_fast_mode(true)
	var exile_state: Variant = exile_duel.get("duel_state")
	var cang_hand: Array = exile_state.get_hand(Rules.PLAYER_OWNER)
	var cang_card: Dictionary = cang_hand[0]
	(cang_card.get("active_abilities", []) as Array).append({
		"retained_on_flip": true,
		"triggers": [{
			"event": Catalog.CARD_BE_ATTACKED,
			"conditions": [{"type": Catalog.CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": Catalog.ACTION_EXILE_ATTACKED_CARD}],
		}],
	})
	var cang_view: Control = _cards_below(exile_duel.get_node("DuelCanvas/PlayerHand"))[0]
	cang_view.call("sync_runtime_data", cang_card, Rules.PLAYER_OWNER)
	_check(await exile_duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 4, false), "Reaction-exile fixture places augmented CangSong")
	_check(await exile_duel.debug_commit_move(Rules.OPPONENT_OWNER, 1, 5, false), "Reaction-exile target commits through production")
	await process_frame
	_check(exile_duel.debug_get_board_occupancy() == 1, "Reaction exile removes the summoned card from logical board")
	_check(not exile_duel.debug_has_board_card_view(5), "Reaction exile clears the summoned card view")
	_check(exile_duel.debug_get_removed_count(Rules.OPPONENT_OWNER) == 1, "Reaction exile records the opponent card")
	_check(
		&"card_exiled" in exile_duel.debug_get_presentation_trace(),
		"Reaction exile uses the existing removal presentation"
	)
	var reaction_exile_trace: Array[StringName] = exile_duel.debug_get_presentation_trace()
	_check(
		reaction_exile_trace.rfind(&"attack_started")
		< reaction_exile_trace.rfind(&"card_exiled"),
		"Reaction attack stroke remains visible before intercepted exile"
	)
	_check(
		exile_duel.debug_get_attack_vfx_trace().size() == 1,
		"Reaction exile still plays one attempted-attack stroke"
	)
	var exile_cang_instance_id: StringName = exile_duel.debug_get_board_card_instance_id(4)
	_check(
		exile_duel.debug_get_ability_pulse_trace().count(exile_cang_instance_id) == 1,
		"Consecutive reaction and exile triggers from one card pulse only once"
	)
	exile_duel.queue_free()
	await process_frame


func _check_ability_pulse_sequencing() -> void:
	var duel: Node = _instantiate_duel()
	root.add_child(duel)
	await process_frame
	await process_frame
	duel.debug_set_fast_mode(true)
	_check(await duel.debug_commit_move(Rules.PLAYER_OWNER, 0, 0, false), "Pulse fixture places source A")
	_check(await duel.debug_commit_move(Rules.OPPONENT_OWNER, 0, 8, false), "Pulse fixture places source B")
	var source_a: StringName = duel.debug_get_board_card_instance_id(0)
	var source_b: StringName = duel.debug_get_board_card_instance_id(8)
	var baseline_size: int = duel.debug_get_ability_pulse_trace().size()
	var synthetic_events: Array = [
		{"type": &"ability_triggered", "source_instance_id": source_a},
		{"type": &"ability_triggered", "source_instance_id": source_a},
		{"type": &"ability_triggered", "source_instance_id": source_b},
		{"type": &"ability_triggered", "source_instance_id": source_a},
		{"type": &"ability_triggered", "source_instance_id": &"missing_source"},
	]
	await duel.call("_present_transition_events", synthetic_events, Rules.PLAYER_OWNER)
	var first_trace: Array[StringName] = duel.debug_get_ability_pulse_trace()
	_check(
		first_trace.slice(baseline_size) == [source_a, source_b, source_a],
		"One move suppresses A-A, permits A-B-A, and ignores a missing source"
	)
	await duel.call(
		"_present_transition_events",
		[{"type": &"ability_triggered", "source_instance_id": source_a}],
		Rules.PLAYER_OWNER
	)
	var second_trace: Array[StringName] = duel.debug_get_ability_pulse_trace()
	_check(
		second_trace.size() == first_trace.size() + 1 and second_trace[-1] == source_a,
		"Pulse suppression resets before the next move"
	)
	var attack_trace_size: int = duel.debug_get_attack_vfx_trace().size()
	await duel.call(
		"_present_transition_events",
		[
			{
				"type": &"attack_started",
				"source_cell": 0,
				"source_instance_id": source_a,
				"target_cell": 2,
				"target_instance_id": &"synthetic_far_target",
			},
			{
				"type": &"attack_started",
				"source_cell": 0,
				"source_instance_id": &"missing_source",
				"target_cell": 2,
				"target_instance_id": &"synthetic_far_target",
			},
			{"type": &"card_moved"},
		],
		Rules.PLAYER_OWNER
	)
	_check(
		duel.debug_get_attack_vfx_trace().size() == attack_trace_size + 1,
		"Valid synthetic attack plays once while a missing source skips without delay"
	)
	_check(
		bool(duel.get_node("DuelCanvas/AttackVfx").call("debug_is_clean")),
		"Controller attack playback leaves no residual overlay"
	)
	duel.queue_free()
	await process_frame


func _check_remaining_card_sizes(container: Node, expected_sizes: Dictionary) -> void:
	var sizes_are_stable: bool = true
	var observed_sizes: Array[String] = []
	for slot: Node in container.get_children():
		for card: Control in _cards_below(slot):
			var expected_size: Vector2 = expected_sizes.get(String(slot.name), Vector2.ZERO)
			sizes_are_stable = sizes_are_stable and card.size.is_equal_approx(expected_size)
			observed_sizes.append("%s=%s" % [slot.name, card.size])
	_check(sizes_are_stable, "%s cards keep their original per-slot size when a slot becomes empty (observed %s)" % [container.name, ", ".join(observed_sizes)])


func _card_sizes_by_slot(container: Node) -> Dictionary:
	var sizes: Dictionary = {}
	for slot: Node in container.get_children():
		for card: Control in _cards_below(slot):
			sizes[String(slot.name)] = card.size
	return sizes


func _first_card(container: Node) -> Control:
	var cards: Array[Control] = _cards_below(container)
	return cards[0] if not cards.is_empty() else null


func _cards_below(container: Node) -> Array[Control]:
	var cards: Array[Control] = []
	for child: Node in container.get_children():
		if child.get_script() == CARD_SCRIPT:
			cards.append(child as Control)
		else:
			cards.append_array(_cards_below(child))
	return cards


func _count_cards(container: Node) -> int:
	return _cards_below(container).size()


func _count_playable(cards: Array[Control]) -> int:
	var count: int = 0
	for card: Control in cards:
		if bool(card.get("playable")):
			count += 1
	return count


func _count_face_down(cards: Array[Control]) -> int:
	var count: int = 0
	for card: Control in cards:
		if card.has_method("is_face_down") and bool(card.call("is_face_down")):
			count += 1
	return count


func _instantiate_duel() -> Node:
	var duel: Node = DUEL_SCENE.instantiate()
	duel.set("deck_profile_path", TEST_PROFILE_PATH)
	duel.set("testing_mode", false)
	duel.set("opponent_hand_shuffle_seed", -1)
	return duel


func _cleanup_test_profile() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_PROFILE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
