extends SceneTree
## Regenerates the placeholder sound effects in res://audio/sfx.
## Run: godot --headless --path . -s res://tools/generate_placeholder_sfx.gd
## (then `godot --headless --path . --import` so Godot imports the new files).

const MIX_RATE := 44100
const OUTPUT_DIR := "res://audio/sfx/"
const MASTER_GAIN := 0.6


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	# Fire is rendered at pitch 1; weapons shift it with AudioStreamPlayer.pitch_scale.
	_save("fire", 0.13, [_noise(0.12, 0.5, 3500.0, 400.0), _tone(120.0, 40.0, 0.08, 0.4, "sine")])
	_save("hit", 0.07, [_tone(1400.0, 900.0, 0.06, 0.25, "square")])
	_save("jump", 0.13, [_tone(220.0, 440.0, 0.12, 0.2, "triangle")])
	_save("footstep", 0.07, [_noise(0.06, 0.15, 800.0, 800.0)])
	_save("pickup", 0.17, [_tone(500.0, 500.0, 0.08, 0.2, "triangle"), _tone(900.0, 900.0, 0.09, 0.2, "triangle", 0.07)])
	_save("reload", 0.26, [_tone(260.0, 180.0, 0.07, 0.18, "square"), _tone(320.0, 220.0, 0.07, 0.18, "square", 0.18)])
	quit()


func _save(sound_name: String, length: float, layers: Array) -> void:
	var samples := PackedFloat32Array()
	samples.resize(int(length * MIX_RATE))
	for layer: Dictionary in layers:
		var offset: int = layer["offset"]
		var data: PackedFloat32Array = layer["samples"]
		for i in data.size():
			if offset + i < samples.size():
				samples[offset + i] += data[i]

	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * MASTER_GAIN, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	var path := OUTPUT_DIR + sound_name + ".wav"
	print("%s -> %s" % [path, error_string(stream.save_to_wav(path))])


## Low-passed noise with an exponential gain decay; the filter cutoff ramps exponentially.
func _noise(duration: float, peak: float, cutoff_start: float, cutoff_end: float, delay := 0.0) -> Dictionary:
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var filtered := 0.0
	for i in count:
		var t := float(i) / count
		var cutoff := cutoff_start * pow(cutoff_end / cutoff_start, t)
		var alpha := 1.0 - exp(-TAU * cutoff / MIX_RATE)
		filtered += alpha * (randf_range(-1.0, 1.0) - filtered)
		samples[i] = filtered * peak * pow(0.001 / peak, t) * 2.0
	return {"offset": int(delay * MIX_RATE), "samples": samples}


## Oscillator with exponentially ramped frequency and gain.
func _tone(freq_start: float, freq_end: float, duration: float, peak: float, shape: String, delay := 0.0) -> Dictionary:
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += TAU * freq_start * pow(freq_end / freq_start, t) / MIX_RATE
		var wave: float
		match shape:
			"square":
				wave = signf(sin(phase))
			"triangle":
				wave = asin(sin(phase)) * 2.0 / PI
			_:
				wave = sin(phase)
		samples[i] = wave * peak * pow(0.001 / peak, t)
	return {"offset": int(delay * MIX_RATE), "samples": samples}
