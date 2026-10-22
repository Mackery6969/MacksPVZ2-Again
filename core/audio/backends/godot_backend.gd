extends AudioBackend
## Plays events through Godot's own audio, using each event's `streams`.
##
## This is the stopgap while FMOD is not installed: good enough to hear the
## game, and it exercises the same event names FMOD will use, so nothing has
## to change when the real backend arrives.
##
## The clips come from the Music submodule (`res://Music/Assets/...`), listed
## per event in the pack's generated `audio/streams.json`. Without the
## submodule checked out - or with its LFS files still pointers - nothing
## loads and the game is silent, exactly as before.
##
## What it cannot do is anything FMOD's timeline does: a lawn's music plays its
## first phase's loop and never escalates.

const VOICES := 16

var _root: Node = null
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _music_event: StringName = &""
var _next_voice: int = 0
var _streams: Dictionary = {}     ## event id -> AudioStream, once loaded


func backend_name() -> String:
	return "godot"


func setup(catalog: AudioCatalog) -> void:
	_root = Node.new()
	_root.name = "GodotAudioBackend"
	# Audio keeps time with the player, not with fast forward or a pause.
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.get_main_loop().root.add_child.call_deferred(_root)

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		_root.add_child.call_deferred(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_root.add_child.call_deferred(_music)

	# Effects are preloaded, so the first of each does not hitch. Music is
	# loaded when it is first asked for: every world's cues at once would be
	# a few hundred megabytes nobody is listening to.
	for id in catalog.events:
		var event: AudioEvent = catalog.events[id]
		if not event.is_music:
			_stream_for(event)


## The event's stream, built and cached on first use. A missing file is not
## fatal, it is just silent.
func _stream_for(event: AudioEvent) -> AudioStream:
	if not _streams.has(event.id):
		_streams[event.id] = _build(event)
	return _streams[event.id]


## One clip as is, or several behind a randomizer so each play picks one.
func _build(event: AudioEvent) -> AudioStream:
	var clips: Array[AudioStream] = []
	for path in event.streams:
		if not ResourceLoader.exists(path):
			continue
		var clip = load(path)
		if clip is AudioStream:
			clips.append(_looped(clip) if event.loop else clip)
	if clips.is_empty():
		return null
	if clips.size() == 1:
		return clips[0]
	var pick := AudioStreamRandomizer.new()
	pick.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	pick.random_pitch = 1.0
	for clip in clips:
		pick.add_stream(-1, clip)
	return pick


## A looping copy, leaving the imported resource as it was for anything else
## that plays the same file once.
func _looped(clip: AudioStream) -> AudioStream:
	if not ("loop" in clip):
		return clip
	var copy: AudioStream = clip.duplicate()
	copy.set("loop", true)
	return copy


func can_play(event: AudioEvent) -> bool:
	if _streams.get(event.id) != null:
		return true
	for path in event.streams:
		if ResourceLoader.exists(path):
			return true
	return false


func play(event: AudioEvent, _position: Variant = null) -> void:
	var stream := _stream_for(event)
	if stream == null or _voices.is_empty():
		return
	# Round-robin the voices, so a burst of sounds does not cut itself off.
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = linear_to_db(maxf(event.volume, 0.0001))
	voice.play()


func play_music(event: AudioEvent) -> void:
	var stream := _stream_for(event)
	if stream == null or _music == null:
		return
	# Asking for the cue that is already playing leaves it alone, so a
	# resumed or restarted level does not jump its music back to the top.
	if _music_event == event.id and _music.playing:
		return
	_music_event = event.id
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(event.volume, 0.0001))
	_music.play()


func stop_music() -> void:
	_music_event = &""
	if _music != null:
		_music.stop()


func shutdown() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_voices.clear()
	_music = null
	_music_event = &""
