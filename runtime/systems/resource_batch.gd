class_name ResourceBatch
extends RefCounted

## Safe Godot 4 replacement for the legacy permanent worker thread.
## It uses ResourceLoader's threaded API and polls from the main loop, so there
## is no unmanaged thread to leak or join during shutdown.

signal stage_updated(progress: float)
signal load_finished()
signal load_failed(path: String, message: String)

var _pending_paths: Array[String] = []
var _active_paths: Array[String] = []
var _ready: Dictionary = {}
var _total_progress: float = 0.0
var _loading: bool = false
var _generation: int = 0


func add_resource_to_batch(path: String) -> void:
	if path.is_empty() or _pending_paths.has(path) or _active_paths.has(path):
		return
	_pending_paths.append(path)


func start_loading(p_min_stage_time: int = 100) -> void:
	if _loading:
		return
	if _pending_paths.is_empty():
		_total_progress = 1.0
		stage_updated.emit(_total_progress)
		load_finished.emit()
		return
	_active_paths = _pending_paths.duplicate()
	_pending_paths.clear()
	_ready.clear()
	_total_progress = 0.0
	_loading = true
	_generation += 1
	for path: String in _active_paths:
		# A closed batch cannot stop Godot's threaded request. If a new batch asks
		# for the same path while that request is still running, join its result
		# instead of issuing a second request (which would return ERR_BUSY).
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var error: Error = ResourceLoader.load_threaded_request(path, "", true)
		if error != OK:
			_loading = false
			_active_paths.clear()
			load_failed.emit(path, error_string(error))
			return
	_poll_batch(_generation, maxi(0, p_min_stage_time))


func get_resource(path: String) -> Resource:
	if not _ready.has(path):
		return null
	var resource: Resource = peek_resource(path)
	_ready.erase(path)
	return resource


func peek_resource(path: String) -> Resource:
	if not _ready.has(path):
		return null
	return _ready[path] as Resource


func get_total_progress() -> float:
	return _total_progress


func is_loading() -> bool:
	return _loading


func close() -> void:
	_generation += 1
	_loading = false
	_pending_paths.clear()
	_active_paths.clear()
	_ready.clear()
	_total_progress = 0.0


func _poll_batch(generation: int, min_stage_time_ms: int) -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = main_loop as SceneTree
	if tree == null:
		_loading = false
		_active_paths.clear()
		return
	while _loading and generation == _generation:
		var completed: int = 0
		var progress_sum: float = 0.0
		for path: String in _active_paths:
			var progress_values: Array = []
			var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path, progress_values)
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading = false
				_active_paths.clear()
				load_failed.emit(path, "No se pudo cargar el recurso.")
				return
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				completed += 1
				progress_sum += 1.0
				if not _ready.has(path):
					_ready[path] = ResourceLoader.load_threaded_get(path)
			elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				progress_sum += float(progress_values[0]) if not progress_values.is_empty() else 0.0
		_total_progress = progress_sum / float(_active_paths.size())
		stage_updated.emit(_total_progress)
		if not _loading or generation != _generation:
			return
		if completed == _active_paths.size():
			_loading = false
			# Release the batch before notifying consumers: they may immediately
			# request the same scene again for another level or a retry.
			_active_paths.clear()
			_total_progress = 1.0
			stage_updated.emit(_total_progress)
			if generation != _generation:
				return
			load_finished.emit()
			return
		if min_stage_time_ms > 0:
			await tree.create_timer(float(min_stage_time_ms) / 1000.0).timeout
		else:
			await tree.process_frame
