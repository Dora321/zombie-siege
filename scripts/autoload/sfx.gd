extends Node
## 程序化音频：音效和背景音乐都由代码合成成 AudioStreamWAV，无外部素材。

const RATE := 22050
const POOL_SIZE := 18
## 同一音效的最短触发间隔（毫秒），避免冲锋枪和成群僵尸把声音叠爆。
const MIN_GAP_MS := {
	"hit": 45, "groan": 500, "casing": 60, "wall_hit": 110, "coin": 40, "smg": 40,
	"turret": 70, "base_hit": 160, "ui_hover": 40,
}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_ms := {}
var _music_a: AudioStreamPlayer
var _music_streams := {}
var _music_wanted := ""
var _thread: Thread
var _noise := RandomNumberGenerator.new()
## headless 下没有音频设备，只生成数据不播放。
var _silent := false
## 浏览器在玩家操作之前不允许出声，网页版由标题界面的「点击开始」解锁。
var audio_unlocked := not OS.has_feature("web")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	get_tree().auto_accept_quit = false
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_a = AudioStreamPlayer.new()
	add_child(_music_a)
	_build_sfx()
	# 背景音乐渲染较慢，放到后台线程，避免卡启动。
	# 无线程的网页版没有后台线程，由 _render_song 分摊到多帧。
	if OS.has_feature("threads"):
		_thread = Thread.new()
		_thread.start(_render_all_music)
	else:
		_render_all_music()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	# 退出前释放正在播放的音频流，否则引擎会报资源泄漏
	_music_a.stop()
	_music_a.stream = null
	for p in _players:
		p.stop()
		p.stream = null
	_streams.clear()
	_music_streams.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## 正常退出：先停掉所有声音，留一点时间让音频线程回收播放实例，再退出。
func quit_game() -> void:
	_music_a.stop()
	for p in _players:
		p.stop()
	await get_tree().create_timer(0.12, true, false, true).timeout
	get_tree().quit()


## 播放音效。volume_db 为额外音量，jitter 为随机音高幅度。
func play(sound: String, volume_db := 0.0, jitter := 0.06) -> void:
	if _silent or not Save.sfx_on or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	var gap: int = MIN_GAP_MS.get(sound, 15)
	if now - int(_last_ms.get(sound, -100000)) < gap:
		return
	_last_ms[sound] = now
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.play()


## 切换背景音乐：menu（平静）/ combat（紧张）/ 空串（停止）。
func play_music(track: String) -> void:
	_music_wanted = track
	_apply_music()


func refresh_music() -> void:
	_apply_music()


func _apply_music() -> void:
	if _silent:
		return
	if not Save.music_on or _music_wanted == "":
		_music_a.stop()
		return
	if not _music_streams.has(_music_wanted):
		return
	var s: AudioStream = _music_streams[_music_wanted]
	if _music_a.stream != s or not _music_a.playing:
		_music_a.stream = s
		_music_a.volume_db = -9.0
		_music_a.play()


# ---------------------------------------------------------------------------
# 合成基础
# ---------------------------------------------------------------------------

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## 在缓冲区叠加一个音。wave: sq / saw / tri / sin / noise。频率从 f0 滑到 f1，
## noise 的频率是采样保持频率，越低越沉闷。
func _voice(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, wave: String, vol: float, decay := 3.0, vibrato := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var offset := int(start * RATE)
	var phase := 0.0
	var hold := 0.0
	var held := 0.0
	var wave_id: int = {"sq": 0, "saw": 1, "tri": 2, "sin": 3, "noise": 4}[wave]
	for i in n:
		var at := offset + i
		if at >= b.size():
			break
		var t := float(i) / n
		var freq := lerpf(f0, f1, t)
		if vibrato > 0.0:
			freq *= 1.0 + sin(i * 0.0035) * vibrato
		var s := 0.0
		match wave_id:
			0:
				s = 1.0 if phase < 0.5 else -1.0
			1:
				s = phase * 2.0 - 1.0
			2:
				s = absf(phase * 4.0 - 2.0) - 1.0
			3:
				s = sin(phase * TAU)
			4:
				hold += freq / RATE
				if hold >= 1.0:
					hold -= 1.0
					held = _noise.randf_range(-1.0, 1.0)
				s = held
		phase = fmod(phase + freq / RATE, 1.0)
		var env := pow(1.0 - t, decay) * minf(1.0, i / 40.0)
		b[at] += s * vol * env
	return b


func _wav(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = b.size()
	return w


func _add(sound: String, b: PackedFloat32Array) -> void:
	_streams[sound] = _wav(b)


func _build_sfx() -> void:
	var b := _buf(0.16)
	b = _voice(b, 0, 0.13, 9000, 1400, "noise", 0.55)
	b = _voice(b, 0, 0.09, 460, 90, "sq", 0.3)
	_add("pistol", b)

	b = _buf(0.36)
	b = _voice(b, 0, 0.32, 7000, 350, "noise", 0.8, 2.2)
	b = _voice(b, 0, 0.26, 170, 38, "sin", 0.8)
	_add("shotgun", b)

	b = _buf(0.09)
	b = _voice(b, 0, 0.08, 11000, 2600, "noise", 0.42)
	b = _voice(b, 0, 0.05, 620, 180, "sq", 0.18)
	_add("smg", b)

	b = _buf(0.09)
	b = _voice(b, 0, 0.07, 8000, 2800, "noise", 0.3)
	b = _voice(b, 0, 0.06, 980, 320, "sq", 0.16)
	_add("turret", b)

	b = _buf(0.26)
	b = _voice(b, 0, 0.04, 5000, 2500, "noise", 0.4)
	b = _voice(b, 0.15, 0.05, 3400, 1800, "noise", 0.45)
	_add("reload", b)

	b = _buf(0.12)
	b = _voice(b, 0, 0.05, 2400, 1400, "noise", 0.45)
	b = _voice(b, 0.04, 0.07, 900, 1250, "sq", 0.22)
	_add("reload_done", b)

	b = _buf(0.05)
	b = _voice(b, 0, 0.04, 1900, 1500, "sq", 0.22)
	_add("empty", b)

	b = _buf(0.08)
	b = _voice(b, 0, 0.03, 3600, 3100, "sin", 0.2)
	b = _voice(b, 0.035, 0.04, 3000, 2800, "sin", 0.12)
	_add("casing", b)

	b = _buf(0.08)
	b = _voice(b, 0, 0.07, 3500, 700, "noise", 0.4)
	b = _voice(b, 0, 0.06, 240, 90, "sq", 0.24)
	_add("hit", b)

	b = _buf(0.36)
	b = _voice(b, 0, 0.32, 240, 50, "saw", 0.34, 2.0)
	b = _voice(b, 0, 0.16, 1800, 300, "noise", 0.4)
	_add("zombie_die", b)

	b = _buf(0.75)
	b = _voice(b, 0, 0.72, 118, 72, "saw", 0.24, 1.2, 0.09)
	b = _voice(b, 0, 0.72, 177, 108, "saw", 0.09, 1.5, 0.06)
	_add("groan", b)

	b = _buf(0.85)
	b = _voice(b, 0, 0.8, 3200, 110, "noise", 0.9, 1.6)
	b = _voice(b, 0, 0.7, 110, 24, "sin", 0.95, 1.5)
	_add("explode", b)

	b = _buf(0.24)
	b = _voice(b, 0, 0.2, 900, 3600, "noise", 0.32)
	b = _voice(b, 0, 0.14, 300, 620, "sq", 0.12)
	_add("spit", b)

	b = _buf(0.2)
	b = _voice(b, 0, 0.18, 2600, 500, "noise", 0.4)
	_add("splat", b)

	b = _buf(0.22)
	b = _voice(b, 0, 0.2, 320, 110, "sq", 0.36)
	b = _voice(b, 0, 0.1, 2400, 800, "noise", 0.32)
	_add("hurt", b)

	b = _buf(0.3)
	b = _voice(b, 0, 0.26, 170, 62, "sq", 0.32)
	b = _voice(b, 0, 0.18, 4200, 900, "noise", 0.3)
	_add("base_hit", b)

	b = _buf(0.12)
	b = _voice(b, 0, 0.1, 1900, 480, "noise", 0.3)
	b = _voice(b, 0, 0.08, 130, 80, "tri", 0.34)
	_add("wall_hit", b)

	b = _buf(0.42)
	b = _voice(b, 0, 0.4, 1700, 170, "noise", 0.65, 1.8)
	b = _voice(b, 0, 0.26, 95, 45, "sin", 0.6)
	_add("wall_break", b)

	b = _buf(0.15)
	b = _voice(b, 0, 0.05, 988, 988, "sq", 0.18, 0.5)
	b = _voice(b, 0.05, 0.1, 1319, 1319, "sq", 0.18)
	_add("coin", b)

	b = _buf(0.25)
	b = _voice(b, 0, 0.07, 523, 523, "sq", 0.2, 0.5)
	b = _voice(b, 0.07, 0.07, 659, 659, "sq", 0.2, 0.5)
	b = _voice(b, 0.14, 0.11, 1047, 1047, "sq", 0.22)
	_add("buy", b)

	b = _buf(0.2)
	b = _voice(b, 0, 0.09, 190, 170, "sq", 0.24, 0.6)
	b = _voice(b, 0.1, 0.09, 150, 130, "sq", 0.24, 0.6)
	_add("deny", b)

	b = _buf(0.2)
	b = _voice(b, 0, 0.18, 900, 5200, "noise", 0.26, 1.6)
	_add("dash", b)

	b = _buf(1.3)
	b = _voice(b, 0, 0.62, 300, 620, "saw", 0.2, 0.6)
	b = _voice(b, 0.62, 0.66, 620, 290, "saw", 0.2, 1.4)
	_add("siren", b)

	b = _buf(0.9)
	var notes := [523.0, 659.0, 784.0, 1047.0]
	for i in notes.size():
		b = _voice(b, i * 0.12, 0.3 if i < 3 else 0.5, notes[i], notes[i], "sq", 0.2, 1.4)
	_add("wave_clear", b)

	b = _buf(0.05)
	b = _voice(b, 0, 0.04, 880, 660, "sq", 0.16)
	_add("ui_click", b)

	b = _buf(0.03)
	b = _voice(b, 0, 0.025, 520, 520, "tri", 0.08)
	_add("ui_hover", b)

	b = _buf(1.3)
	b = _voice(b, 0, 1.25, 105, 48, "saw", 0.55, 1.2, 0.12)
	b = _voice(b, 0, 1.0, 700, 180, "noise", 0.4, 1.4)
	_add("boss_roar", b)

	b = _buf(1.6)
	var fall := [392.0, 349.0, 311.0, 233.0]
	for i in fall.size():
		b = _voice(b, i * 0.3, 0.55 if i < 3 else 0.7, fall[i], fall[i] * 0.97, "saw", 0.22, 1.2)
	_add("game_over", b)

	b = _buf(1.5)
	var up := [523.0, 523.0, 659.0, 784.0, 1047.0, 1319.0]
	for i in up.size():
		b = _voice(b, i * 0.15, 0.32 if i < 5 else 0.6, up[i], up[i], "sq", 0.2, 1.2)
	_add("victory", b)


# ---------------------------------------------------------------------------
# 背景音乐：后台线程渲染的芯片音乐循环
# ---------------------------------------------------------------------------

func _render_all_music() -> void:
	var menu: AudioStreamWAV = await _render_song(84.0, [45, 41, 48, 43], false)
	_on_music_ready.call_deferred("menu", menu)
	var combat: AudioStreamWAV = await _render_song(138.0, [45, 45, 48, 45, 41, 41, 43, 44], true)
	_on_music_ready.call_deferred("combat", combat)


func _on_music_ready(track: String, stream: AudioStreamWAV) -> void:
	_music_streams[track] = stream
	_apply_music()


func _midi(n: int) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)


func _render_song(bpm: float, roots: Array, intense: bool) -> AudioStreamWAV:
	var step := 60.0 / bpm / 2.0
	var bars := roots.size()
	var total := step * 8 * bars
	var b := _buf(total + 0.001)
	b.resize(int(total * RATE))
	var minor := [0, 3, 7, 12, 7, 3, 10, 7]
	for bar in bars:
		if _thread == null:
			await get_tree().process_frame
		var root: int = roots[bar]
		for s in 8:
			var t := (bar * 8 + s) * step
			# 贝斯
			if intense or s % 2 == 0:
				var bass_note := root - 12 + (12 if intense and s % 4 == 3 else 0)
				b = _voice(b, t, step * (0.9 if intense else 1.8), _midi(bass_note), _midi(bass_note), "sq" if intense else "tri", 0.16 if intense else 0.26, 1.2)
			# 琶音
			if intense:
				if s % 2 == 1 or bar % 2 == 1:
					var arp: int = root + 12 + minor[(s + bar) % minor.size()]
					b = _voice(b, t, step * 0.7, _midi(arp), _midi(arp), "sq", 0.05, 2.0)
			elif s % 2 == 0:
				var arp: int = root + 12 + minor[(s / 2 + bar) % 4]
				b = _voice(b, t, step * 1.6, _midi(arp), _midi(arp), "tri", 0.11, 1.8)
			# 鼓
			if intense:
				if s % 4 == 0:
					b = _voice(b, t, 0.14, 130, 40, "sin", 0.5, 2.0)
				if s % 4 == 2:
					b = _voice(b, t, 0.12, 5200, 1800, "noise", 0.22, 2.2)
				b = _voice(b, t, 0.03, 9000, 7000, "noise", 0.06, 2.0)
			elif s == 0:
				b = _voice(b, t, 0.3, 90, 40, "sin", 0.28, 2.0)
	return _wav(b, true)
