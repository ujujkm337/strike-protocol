extends SceneTree
## Прогон главной сцены несколько кадров. Ловит то, что не видит парсер:
## обращения к несуществующим свойствам, null-ноды, битые NodePath.

var _frames := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/ui/main_menu.tscn")
	if ps == null:
		printerr("FAIL: меню не грузится"); quit(1); return
	var inst := ps.instantiate()
	if inst == null:
		printerr("FAIL: instantiate -> null"); quit(1); return
	get_root().add_child(inst)
	print("меню добавлено в дерево: %s" % (inst != null))


func _process(_d: float) -> bool:
	_frames += 1
	if _frames >= 12:
		var root := get_root().get_child(get_root().get_child_count() - 1)
		var menu := root.get_node_or_null("MenuPanel/Menu")
		var btns := 0
		if menu:
			for c in menu.get_children():
				if c is Button: btns += 1
		var join := root.get_node_or_null("JoinPanel")
		print("кадров прогнано: %d | кнопок меню: %d | панель входа скрыта: %s"
			% [_frames, btns, (not join.visible) if join else "нет панели"])
		# вёрстка: панель меню не должна быть прижата к нижнему краю на всю ширину
		# Вёрстка проверяется по ЯКОРЯМ, а не по position: в headless окно имеет
		# высоту не 1080, и любые абсолютные числа тут были бы лжерезультатом.
		var panel := root.get_node_or_null("MenuPanel") as Control
		var brand := root.get_node_or_null("Brand") as Control
		var ok_layout: bool = panel != null and brand != null
		if ok_layout:
			# панель меню: приянута к правому краю, узкая (280..520), не у нижнего края
			var w: float = absf(panel.offset_right - panel.offset_left)
			ok_layout = panel.anchor_left > 0.9 and panel.anchor_right > 0.9 \
				and w >= 280.0 and w <= 560.0 \
				and panel.anchor_top > 0.2 and panel.anchor_top < 0.75 \
				and panel.offset_top > 80.0 \
				and (panel.offset_bottom - panel.offset_top) > 200.0 \
				and brand.anchor_top < 0.2 and brand.offset_top > 20.0
		var btns_with_min := 0
		for c in (menu.get_children() if menu else []):
			if c is Button and (c as Control).custom_minimum_size.x >= 200.0:
				btns_with_min += 1
		var vp := root.get_node_or_null("Backdrop/World/Viewport") as SubViewport
		var box := root.get_node_or_null("Backdrop/ViewportBox") as SubViewportContainer
		var gfx := root.get_node_or_null("MenuPanel/Menu/GfxMode") as Button
		print("MenuPanel: anchor=(%.2f,%.2f) offsets=(%.0f,%.0f,%.0f,%.0f) | Brand anchor_top=%.2f off=%.0f"
			% [panel.anchor_left, panel.anchor_top, panel.offset_left, panel.offset_top,
				panel.offset_right, panel.offset_bottom, brand.anchor_top, brand.offset_top])
		print("SubViewport=%s контейнер=%s | кнопок с min_width=%d | кнопка графики=%s"
			% [vp != null, box != null, btns_with_min, gfx != null])
		var ok: bool = btns >= 6 and btns_with_min >= 6 and ok_layout and gfx != null
		print("ИТОГ: %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
		return true
	return false   # true = остановить обработку кадров; счётчик бы встал
