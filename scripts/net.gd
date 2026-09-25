extends Node
## 온라인 같이 하기. 중계 서버에 WebSocket으로 붙어 방을 만들거나 들어간다.
## 게임은 방장(host) 쪽에서 돌아간다. 손님(guest)은 키 입력을 보내고, 방장이 보내는 화면 상태를 받아 그린다.

signal status(text: String)
signal room_created(code: String)
signal paired
signal failed(text: String)
signal message(data: Dictionary)
signal peer_left

const DEFAULT_URL := "wss://hotdog-relay.onrender.com"

var url := DEFAULT_URL
var ws: WebSocketPeer
var online := false          # 짝이 지어져 같이 하는 중
var is_host := false
var role := "chef"           # 내 역할
var pending_action := ""     # 연결되면 보낼 요청 (host / join)
var pending_code := ""

# 방장 쪽: 손님이 보낸 입력
var remote_move := Vector2.ZERO
var remote_presses := {"act": 0, "skill": 0}
var _last_counts := {"a": 0, "s": 0}

# 손님 쪽: 가장 최근 화면 상태
var snapshot = null

func _ready() -> void:
	if Session.args.has("server"):
		url = Session.args["server"]

func host(my_role: String) -> void:
	role = my_role
	is_host = true
	_open("host", "")

func join(code: String) -> void:
	is_host = false
	_open("join", code)

func _open(action: String, code: String) -> void:
	leave()
	pending_action = action
	pending_code = code
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		failed.emit("서버에 연결하지 못했어요.")
		ws = null
		return
	status.emit("서버에 연결하는 중... (서버가 자고 있으면 1분쯤 걸려요)")

func leave() -> void:
	if ws:
		ws.close()
	ws = null
	online = false
	snapshot = null
	pending_action = ""

func send(d: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))

## 방장 쪽 캐릭터가 손님의 버튼 입력을 한 번씩 꺼내 쓴다.
func consume(action: String) -> bool:
	if remote_presses[action] > 0:
		remote_presses[action] -= 1
		if Session.args.has("log"):
			print("[net] 손님 입력: ", action)
		return true
	return false

func _process(_delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and pending_action != "":
		if pending_action == "host":
			send({"t": "host"})
		else:
			send({"t": "join", "code": pending_code})
		pending_action = ""
	while ws and ws.get_available_packet_count() > 0:
		var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if d is Dictionary:
			_handle(d)
	if ws and st == WebSocketPeer.STATE_CLOSED:
		var was_online := online
		ws = null
		online = false
		if was_online:
			peer_left.emit()
		else:
			failed.emit("서버 연결이 끊겼어요. 잠시 뒤 다시 해 주세요.")

func _handle(d: Dictionary) -> void:
	match d.get("t", ""):
		"room":
			room_created.emit(d.code)
			status.emit("친구를 기다리는 중...")
		"paired":
			online = true
			remote_move = Vector2.ZERO
			remote_presses = {"act": 0, "skill": 0}
			_last_counts = {"a": 0, "s": 0}
			paired.emit()
			if is_host:
				# 방장이 판을 연다. 손님은 남은 역할을 맡는다
				send({"k": "start", "role": "dog" if role == "chef" else "chef"})
				Session.mode = "online"
				get_tree().change_scene_to_file("res://scenes/main.tscn")
		"error":
			failed.emit(d.msg)
		"left":
			online = false
			peer_left.emit()
	match d.get("k", ""):
		"in":
			remote_move = Vector2(d.mx, d.my)
			var a := int(d.a)
			var s := int(d.s)
			remote_presses.act += maxi(a - _last_counts.a, 0)
			remote_presses.skill += maxi(s - _last_counts.s, 0)
			_last_counts = {"a": a, "s": s}
		"snap":
			snapshot = d
		"start":
			role = d.role
			Session.mode = "online"
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"restart":
			if get_tree().current_scene and get_tree().current_scene.name == "Main":
				get_tree().reload_current_scene()
		_:
			if d.has("k"):
				message.emit(d)
