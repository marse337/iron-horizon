class_name SfxSynth
extends Node

## Procedural Military Arcade Sound Synthesizer
## Generates 16-bit PCM AudioStreamWAV buffers in memory so the game requires
## zero external audio files and works reliably in WebGL/GitHub Pages builds.

const MIX_RATE: int = 22050
const POOL_SIZE: int = 16

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20000101
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_all_sounds()

func play(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not _streams.has(sound_name):
		return
	var p: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % POOL_SIZE
	p.stream = _streams[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()

func _build_all_sounds() -> void:
	_streams["mg_fire"] = _make_mg_fire()
	_streams["ciws_fire"] = _make_ciws_fire()
	_streams["cannon_fire"] = _make_cannon_fire()
	_streams["pistol_fire"] = _make_pistol_fire()
	_streams["ricochet"] = _make_ricochet()
	_streams["sam_lock_beep"] = _make_tone_beep(1180.0, 0.055, 0.35)
	_streams["sam_locked"] = _make_dual_beep(1680.0, 2120.0, 0.11, 0.42)
	_streams["sam_launch"] = _make_sam_launch()
	_streams["explosion_small"] = _make_explosion(0.38, 130.0, 0.7)
	_streams["explosion_large"] = _make_explosion(0.78, 72.0, 0.95)
	_streams["water_splash"] = _make_water_splash()
	_streams["supply_pickup"] = _make_supply_chime()
	_streams["bunker_hit"] = _make_bunker_hit()
	_streams["flare_launch"] = _make_flare_launch()
	_streams["wave_clear"] = _make_wave_clear()

func _create_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var byte_data := PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped: float = clampf(samples[i], -1.0, 1.0)
		var pcm: int = int(clamped * 32767.0)
		byte_data.encode_s16(i * 2, pcm)
	wav.data = byte_data
	return wav

func _make_mg_fire() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.09)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 38.0)
		var freq: float = lerpf(210.0, 62.0, clampf(t * 14.0, 0.0, 1.0))
		phase += freq / float(MIX_RATE)
		var thump: float = sin(phase * TAU) * 0.65
		var crack: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.75
		out[i] = (thump + crack) * env * 0.85
	return _create_wav(out)

func _make_ciws_fire() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.055)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 52.0)
		var buzz: float = signf(sin(t * 340.0 * TAU)) * 0.45
		var noise: float = _rng.randf_range(-1.0, 1.0) * 0.55
		out[i] = (buzz + noise) * env * 0.75
	return _create_wav(out)

func _make_cannon_fire() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.58)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var n_prev: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 6.5)
		var sub_freq: float = lerpf(135.0, 34.0, clampf(t * 4.5, 0.0, 1.0))
		phase += sub_freq / float(MIX_RATE)
		var sub: float = sin(phase * TAU) * 0.75
		var raw_noise: float = _rng.randf_range(-1.0, 1.0)
		n_prev = lerpf(n_prev, raw_noise, 0.22)
		var breech_ring: float = sin(t * 680.0 * TAU) * exp(-t * 24.0) * 0.25
		out[i] = (sub + n_prev * 0.85 + breech_ring) * env * 0.95
	return _create_wav(out)

func _make_pistol_fire() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.11)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 34.0)
		var pop: float = sin(t * lerpf(520.0, 140.0, t * 9.0) * TAU) * 0.55
		var snap: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 65.0) * 0.65
		out[i] = (pop + snap) * env * 0.7
	return _create_wav(out)

func _make_ricochet() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 18.0)
		var freq: float = lerpf(2600.0, 920.0, t / 0.18) + sin(t * 95.0) * 180.0
		phase += freq / float(MIX_RATE)
		out[i] = sin(phase * TAU) * env * 0.45
	return _create_wav(out)

func _make_tone_beep(freq: float, duration: float, amp: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = clampf(1.0 - (t / duration) * 0.5, 0.0, 1.0)
		out[i] = (sin(t * freq * TAU) * 0.7 + signf(sin(t * freq * TAU)) * 0.3) * env * amp
	return _create_wav(out)

func _make_dual_beep(f1: float, f2: float, duration: float, amp: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var freq: float = f1 if t < duration * 0.5 else f2
		out[i] = sin(t * freq * TAU) * amp
	return _create_wav(out)

func _make_sam_launch() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(count)
	var n_prev: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = sin(clampf(t / 0.55, 0.0, 1.0) * PI)
		var raw: float = _rng.randf_range(-1.0, 1.0)
		n_prev = lerpf(n_prev, raw, 0.38)
		var sweep: float = sin(t * lerpf(320.0, 880.0, t / 0.55) * TAU) * 0.25
		out[i] = (n_prev * 0.8 + sweep) * env * 0.75
	return _create_wav(out)

func _make_explosion(duration: float, base_freq: float, gain: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var low_noise: float = 0.0
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * (4.2 / duration))
		var raw: float = _rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, raw, 0.14)
		var f: float = lerpf(base_freq, 26.0, clampf(t / duration, 0.0, 1.0))
		phase += f / float(MIX_RATE)
		var rumble: float = sin(phase * TAU) * 0.65
		out[i] = (low_noise * 0.85 + rumble) * env * gain
	return _create_wav(out)

func _make_water_splash() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.34)
	var out := PackedFloat32Array()
	out.resize(count)
	var filt: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 9.5)
		filt = lerpf(filt, _rng.randf_range(-1.0, 1.0), 0.45)
		out[i] = filt * env * 0.5
	return _create_wav(out)

func _make_supply_chime() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.42)
	var out := PackedFloat32Array()
	out.resize(count)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var idx: int = clampi(int((t / 0.42) * 4.0), 0, 3)
		var freq: float = notes[idx]
		var env: float = exp(-fmod(t, 0.105) * 14.0)
		out[i] = (sin(t * freq * TAU) * 0.65 + sin(t * freq * 2.0 * TAU) * 0.25) * env * 0.65
	return _create_wav(out)

func _make_bunker_hit() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.32)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 11.0)
		var thud: float = sin(t * lerpf(110.0, 38.0, t / 0.32) * TAU) * 0.8
		var grit: float = _rng.randf_range(-1.0, 1.0) * 0.45
		out[i] = (thud + grit) * env * 0.9
	return _create_wav(out)

func _make_flare_launch() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 8.0)
		var whistle: float = sin(t * lerpf(420.0, 1250.0, t / 0.35) * TAU) * 0.4
		var hiss: float = _rng.randf_range(-1.0, 1.0) * 0.35
		out[i] = (whistle + hiss) * env * 0.65
	return _create_wav(out)

func _make_wave_clear() -> AudioStreamWAV:
	var count: int = int(MIX_RATE * 0.75)
	var out := PackedFloat32Array()
	out.resize(count)
	var freqs: Array[float] = [440.0, 554.37, 659.25, 880.0]
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var env: float = exp(-t * 2.8)
		var sig: float = 0.0
		for f in freqs:
			sig += sin(t * f * TAU) * 0.22
		out[i] = sig * env * 0.8
	return _create_wav(out)

