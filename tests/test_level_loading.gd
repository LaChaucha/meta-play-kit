extends "res://tests/test_case.gd"

const BatchScript: GDScript = preload("res://scripts/systems/resource_batch.gd")
const LEVEL_PATH: String = "res://scenes/level_stub.tscn"


func test_consumed_scene_can_be_loaded_again_for_next_level_and_retry() -> void:
	var batch: ResourceBatch = BatchScript.new()
	watch_signals(batch)
	for load_index: int in range(3):
		batch.add_resource_to_batch(LEVEL_PATH)
		batch.start_loading(0)
		var completed: bool = await wait_until(func() -> bool: return not batch.is_loading())
		if not assert_true(completed, "La carga %d debe finalizar." % load_index):
			batch.close()
			return
		var resource: Resource = batch.get_resource(LEVEL_PATH)
		assert_is(resource, PackedScene, "Cada carga debe entregar una escena instanciable.")
		assert_null(batch.get_resource(LEVEL_PATH), "La extracción consume sólo el resultado del lote actual.")
	assert_signal_emit_count(batch, "load_finished", 3)
	batch.close()


func test_uninstantiable_level_returns_home_without_showing_game() -> void:
	var stage: Node = add_scene("res://scenes/main.tscn")
	var loading: Control = stage.get_node("LoadingOverlay") as Control
	var boot_completed: bool = await wait_until(func() -> bool: return not loading.visible)
	if not assert_true(boot_completed):
		return
	TtpGuiApi.set_levels({
		"invalid_level": {"name": "Nivel inválido", "enabled": true, "scene_path": "res://icon.svg"},
	})
	TtpGuiApi.load_level("invalid_level")
	var load_completed: bool = await wait_until(func() -> bool: return not TtpGuiApi.resource_batch.is_loading())
	if not assert_true(load_completed):
		return
	assert_false(loading.visible, "Un fallo no debe dejar la pantalla de carga bloqueando la UI.")
	var game: Control = stage.get_node("Background/ScreenFrame/ScreenStack/GameScreen") as Control
	var home: Control = stage.get_node("Background/ScreenFrame/ScreenStack/HomeScreen") as Control
	assert_false(game.visible, "La pantalla de juego necesita una instancia válida.")
	assert_true(home.visible)
	assert_eq(stage.get("_current_level_key"), "level1", "Un fallo no debe cambiar el nivel activo.")
