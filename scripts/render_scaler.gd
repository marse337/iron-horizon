class_name RenderScaler
extends Node

## Keeps 3D rendering affordable on phones AND tablets.
##
## The web build renders at devicePixelRatio, so the 3D scene costs whatever the
## screen's physical pixel count is: ~2.5-3 MP on a phone but 4-6 MP on an iPad.
## Tablets often have phone-class GPUs, so they fell behind. This node:
##  1. caps the 3D render resolution to a pixel budget (HUD/menus stay sharp,
##     only the 3D world is upscaled), recomputed on rotate/resize, and
##  2. while a wave is being played, nudges the 3D scale down when the frame rate
##     sags and back up when there is headroom, so weaker devices settle on a
##     scale they can hold.
## Only enabled on mobile/tablet devices; desktops keep full native resolution.

## Most 3D pixels rendered per frame (a 2560x1170 phone is ~3.0 MP)
const PIXEL_BUDGET: float = 2_800_000.0
## Never go blurrier than this
const MIN_SCALE: float = 0.5
## Below this FPS (averaged over a sample window) the scale steps down
const LOW_FPS: float = 48.0
## At or above this FPS the scale may creep back up toward the budget cap
const HIGH_FPS: float = 57.0
const SAMPLE_SECONDS: float = 1.0
const STEP_DOWN: float = 0.88
const STEP_UP: float = 0.05
## Consecutive good windows needed before stepping up
const GOOD_WINDOWS_TO_RAISE: int = 8

var enabled: bool = false
## Set by GameManager: true only while a wave is being played
var measuring: bool = false

var cap_scale: float = 1.0
var current_scale: float = 1.0
# Highest scale that has held up; stepping up past a scale that dropped frames
# is skipped so the scaler doesn't oscillate
var _ceiling: float = 1.0
var _accum_time: float = 0.0
var _accum_frames: int = 0
var _bad_windows: int = 0
var _good_windows: int = 0
# Ignore the first frames after start/resize/state change (shader compiles, hitches)
var _settle: float = 2.0

func _ready() -> void:
	if not enabled:
		return
	var vp: Viewport = get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.size_changed.connect(_on_size_changed)
	_on_size_changed()

func set_measuring(on: bool) -> void:
	if measuring == on:
		return
	measuring = on
	_reset_window()
	_settle = 1.5
	if on:
		# Each wave/resume gets a fresh chance to climb back toward the cap
		_ceiling = cap_scale

func _on_size_changed() -> void:
	var px: Vector2i = DisplayServer.window_get_size()
	var area: float = maxf(1.0, float(px.x) * float(px.y))
	cap_scale = clampf(sqrt(PIXEL_BUDGET / area), MIN_SCALE, 1.0)
	_ceiling = cap_scale
	_apply(minf(current_scale, cap_scale) if current_scale < 1.0 else cap_scale)
	_reset_window()
	_settle = 2.0

func _apply(s: float) -> void:
	current_scale = clampf(snappedf(s, 0.01), MIN_SCALE, cap_scale)
	get_viewport().scaling_3d_scale = current_scale

func _reset_window() -> void:
	_accum_time = 0.0
	_accum_frames = 0

func _process(delta: float) -> void:
	if not enabled or not measuring:
		return
	if _settle > 0.0:
		_settle -= delta
		return
	_accum_time += delta
	_accum_frames += 1
	if _accum_time < SAMPLE_SECONDS:
		return
	var fps: float = _accum_frames / _accum_time
	_reset_window()

	if fps < LOW_FPS:
		_good_windows = 0
		_bad_windows += 1
		if _bad_windows >= 2 and current_scale > MIN_SCALE:
			_ceiling = current_scale - 0.01
			_apply(current_scale * STEP_DOWN)
			_bad_windows = 0
			_settle = 1.0
	elif fps >= HIGH_FPS:
		_bad_windows = 0
		_good_windows += 1
		if _good_windows >= GOOD_WINDOWS_TO_RAISE and current_scale + 0.005 < minf(cap_scale, _ceiling):
			_apply(minf(current_scale + STEP_UP, minf(cap_scale, _ceiling)))
			_good_windows = 0
			_settle = 1.0
	else:
		_bad_windows = 0
		_good_windows = 0
