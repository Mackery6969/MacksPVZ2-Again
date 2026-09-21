extends AudioBackend
## Plays events through Godot's own audio, using each event's `stream_path`.
##
## This is the stopgap while FMOD is not installed: good enough to hear the
## game, and it exercises the same event names FMOD will use, so nothing has
## to change when the real backend arrives.

const VOICES := 16

var _root: Node = null
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _next_voice: int = 0
var _streams: Dictionary = {}     ## path -> AudioStream


func backend_name() -> String:
	return "godot"


func setup(catalog: AudioCatalog) -> void:
	_root = Node.new()
	_root.name = "GodotAudioBackend"
	Engine.get_main_loop().root.add_child.call_deferred(_root)

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		_root.add_child.call_deferred(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_root.add_child.call_deferred(_music)

	# Preload what exists; a missing file is not fatal, it is just silent.
	for id in catalog.events:
		var event: AudioEvent = catalog.events[id]
		if event.stream_path != "" and ResourceLoader.exists(event.stream_path):
			_streams[event.stream_path] = load(event.stream_path)


func play(event: AudioEvent, _position: Variant = null) -> void:
	var stream = _streams.get(event.stream_path)
	if stream == null or _voices.is_empty():
		return
	# Round-robin the voices, so a burst of sounds does not cut itself off.
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = linear_to_db(maxf(event.volume, 0.0001))
	voice.play()


func play_music(event: AudioEvent) -> void:
	var stream = _streams.get(event.stream_path)
	if stream == null or _music == null:
		return
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(event.volume, 0.0001))
	_music.play()


func stop_music() -> void:
	if _music != null:
		_music.stop()


func shutdown() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_voices.clear()
	_music = null
