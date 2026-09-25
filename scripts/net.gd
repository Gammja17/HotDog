extends Node
## 온라인 같이 하기 (웹판). 브라우저끼리 WebRTC로 직접 연결한다.
## 처음 서로 찾는 것만 공개 중개 서버(PeerJS)를 빌려 쓴다. 가입이나 서버 운영이 필요 없다.
## 중개 서버는 PeerJS 모양의 메시지만 전달해 줘서, 우리 말은 CANDIDATE의 candidate 글자 안에 JSON으로 넣어 보낸다.
## 게임은 방장(host) 쪽에서 돌아간다. 손님(guest)은 키 입력을 보내고, 방장이 보내는 화면 상태를 받아 그린다.

signal status(text: String)
signal room_created(code: String)
signal paired
signal failed(text: String)
signal message(data: Dictionary)
signal peer_left

const SIGNAL_URL := "wss://0.peerjs.com/peerjs?key=peerjs&id=%s&token=%s"
const PREFIX := "hotdog-v1-"
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ"
const JOIN_TIMEOUT := 25.0

var online := false          # 짝이 지어져 같이 하는 중
var is_host := false
var role := "chef"           # 내 역할
var room_code := ""

# 방장 쪽: 손님이 보낸 입력
var remote_move := Vector2.ZERO
var remote_look := Vector2.ZERO   # 손님이 셰프일 때: (몸 좌우, 고개 위아래)
var remote_cook: Array = []       # 손님 셰프가 자기 화면에서 판정한 손맛 결과 (true = 초록 칸)
var _last_cook := {"g": 0, "b": 0}
var remote_presses := {"act": 0, "skill": 0, "bark": 0}
var _last_counts := {"a": 0, "s": 0, "b": 0}

# 손님 쪽: 가장 최근 화면 상태
var snapshot = null

var _ws: WebSocketPeer       # 중개 서버
var _hb_t := 0.0
var _peer_sid := ""          # 상대의 중개 id
var _conn: WebRTCPeerConnection
var _chan: WebRTCDataChannel
var _join_t := -1.0

## 브라우저에서만 된다 (데스크톱 exe에는 WebRTC 부품이 없다)
func available() -> bool:
	return OS.has_feature("web")

func host(my_role: String) -> void:
	leave()
	role = my_role
	is_host = true
	room_code = ""
	for i in 4:
		room_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	_ws_connect(PREFIX + room_code.to_lower())
	status.emit("방을 만드는 중...")

func join(code: String) -> void:
	leave()
	is_host = false
	room_code = code.strip_edges().to_upper()
	_peer_sid = PREFIX + room_code.to_lower()
	_join_t = JOIN_TIMEOUT
	_ws_connect(PREFIX + "c%d" % randi())
	status.emit("방 %s에 들어가는 중..." % room_code)

func leave() -> void:
	_ws_close()
	if _chan:
		_chan.close()
	if _conn:
		_conn.close()
	_chan = null
	_conn = null
	online = false
	snapshot = null
	_join_t = -1.0

func send(d: Dictionary) -> void:
	if _chan and _chan.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_chan.put_packet(JSON.stringify(d).to_utf8_buffer())

## 방장 쪽 캐릭터가 손님의 버튼 입력을 한 번씩 꺼내 쓴다.
func consume(action: String) -> bool:
	if remote_presses[action] > 0:
		remote_presses[action] -= 1
		print("[온라인] 손님 입력: ", action)
		return true
	return false

## 초대 링크 (누르면 바로 이 방에 들어온다)
func invite_link() -> String:
	if room_code == "" or not OS.has_feature("web"):
		return ""
	var here := str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	return "%s?join=%s" % [here, room_code]

## 초대 링크로 열었으면 방 코드를 돌려준다
func invited_code() -> String:
	if not OS.has_feature("web"):
		return ""
	var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('join') || ''", true))
	return q.strip_edges().to_upper()

# ---------------------------------------------------------------- 중개 서버

func _ws_connect(id: String) -> void:
	_ws_close()
	_ws = WebSocketPeer.new()
	_hb_t = 5.0
	if _ws.connect_to_url(SIGNAL_URL % [id, str(randi())]) != OK:
		_fail("중개 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.")

func _ws_close() -> void:
	if _ws:
		_ws.close()
	_ws = null

func _ws_send(dst: String, obj: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := {"type": "data", "connectionId": "dc_hotdog", "candidate": {"candidate": JSON.stringify(obj), "sdpMid": "0", "sdpMLineIndex": 0}}
	_ws.send_text(JSON.stringify({"type": "CANDIDATE", "dst": dst, "payload": payload}))

func _fail(text: String) -> void:
	leave()
	failed.emit(text)

func _process(delta: float) -> void:
	if _join_t > 0.0:
		_join_t -= delta
		if _join_t <= 0.0:
			_fail("방에 들어가지 못했어요. 코드를 확인하거나, 네트워크 사정으로 연결이 막혔을 수도 있어요.")
			return
	if _ws:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			while _ws and _ws.get_available_packet_count() > 0:
				var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_on_signal(msg)
			_hb_t -= delta
			if _hb_t <= 0.0 and _ws:
				_hb_t = 5.0
				_ws.send_text(JSON.stringify({"type": "HEARTBEAT"}))
		elif st == WebSocketPeer.STATE_CLOSED:
			_ws = null
			if not online:
				_fail("중개 서버와 연결이 끊겼어요. 잠시 뒤 다시 해 주세요.")
	if _conn:
		_conn.poll()
		if _chan:
			var cs := _chan.get_ready_state()
			if cs == WebRTCDataChannel.STATE_OPEN:
				if not online:
					_on_paired()
				while _chan and _chan.get_available_packet_count() > 0:
					var d = JSON.parse_string(_chan.get_packet().get_string_from_utf8())
					if d is Dictionary:
						_handle(d)
			elif online and cs == WebRTCDataChannel.STATE_CLOSED:
				online = false
				peer_left.emit()
		if online and _conn and _conn.get_connection_state() in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]:
			online = false
			peer_left.emit()

func _on_signal(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"OPEN":
			if is_host:
				print("[온라인] 방 코드 ", room_code)
				room_created.emit(room_code)
				status.emit("친구를 기다리는 중...")
			else:
				_ws_send(_peer_sid, {"k": "join"})
		"ID-TAKEN":
			if is_host:
				host(role)  # 드물게 코드가 겹쳤다
			else:
				_ws_connect(PREFIX + "c%d" % randi())
		"EXPIRE":
			if not is_host and str(msg.get("src", "")) == _peer_sid:
				_fail("방 %s을(를) 찾을 수 없어요. 코드를 다시 확인해 주세요." % room_code)
		"CANDIDATE":
			var inner = msg.get("payload", {}).get("candidate", {}).get("candidate", "")
			var obj = JSON.parse_string(inner) if inner is String else null
			if obj is Dictionary:
				_on_rtc_msg(str(msg.get("src", "")), obj)

func _on_rtc_msg(src: String, m: Dictionary) -> void:
	match m.get("k", ""):
		"join":  # 방장: 누가 들어오고 싶어 한다
			if not is_host:
				return
			if _conn != null:
				_ws_send(src, {"k": "full"})
				return
			_peer_sid = src
			_new_conn()
			if _conn:
				_conn.create_offer()
				status.emit("친구와 연결하는 중...")
		"offer":  # 손님: 방장이 연결 정보를 보냈다
			if is_host or src != _peer_sid or _conn != null:
				return
			_new_conn()
			if _conn:
				_conn.set_remote_description("offer", str(m.get("sdp", "")))
				status.emit("방장과 연결하는 중...")
		"answer":
			if _conn and src == _peer_sid:
				_conn.set_remote_description("answer", str(m.get("sdp", "")))
		"ice":
			if _conn and src == _peer_sid:
				_conn.add_ice_candidate(str(m.get("mid", "")), int(m.get("idx", 0)), str(m.get("cand", "")))
		"full":
			if src == _peer_sid:
				_fail("이미 두 명이 들어간 방이에요.")

func _new_conn() -> void:
	_conn = WebRTCPeerConnection.new()
	if _conn.initialize(ICE) != OK:
		_fail("이 환경에서는 온라인 연결을 쓸 수 없어요. 웹판에서 해 주세요.")
		return
	# 양쪽이 미리 약속한 채널 하나 (순서대로, 빠짐없이)
	_chan = _conn.create_data_channel("game", {"negotiated": true, "id": 1})
	_conn.session_description_created.connect(func(type: String, sdp: String):
		_conn.set_local_description(type, sdp)
		_ws_send(_peer_sid, {"k": type, "sdp": sdp}))
	_conn.ice_candidate_created.connect(func(mid: String, idx: int, cand: String):
		_ws_send(_peer_sid, {"k": "ice", "mid": mid, "idx": idx, "cand": cand}))

func _on_paired() -> void:
	print("[온라인] 연결됨 (", "방장" if is_host else "손님", ")")
	online = true
	_join_t = -1.0
	_ws_close()  # 짝이 지어졌으니 중개 서버는 이제 필요 없다 (방도 닫힌다)
	remote_move = Vector2.ZERO
	remote_presses = {"act": 0, "skill": 0, "bark": 0}
	_last_counts = {"a": 0, "s": 0, "b": 0}
	remote_cook.clear()
	_last_cook = {"g": 0, "b": 0}
	paired.emit()
	if is_host:
		# 방장이 판을 연다. 손님은 남은 역할을 맡는다
		send({"k": "start", "role": "dog" if role == "chef" else "chef"})
		Session.mode = "online"
		get_tree().change_scene_to_file("res://scenes/main.tscn")

# ---------------------------------------------------------------- 게임 메시지

func _handle(d: Dictionary) -> void:
	match d.get("k", ""):
		"in":
			remote_move = Vector2(d.mx, d.my)
			if d.has("yw"):
				remote_look = Vector2(d.yw, d.pt)
			if d.has("cg"):
				for i in maxi(int(d.cg) - _last_cook.g, 0):
					remote_cook.append(true)
				for i in maxi(int(d.cb) - _last_cook.b, 0):
					remote_cook.append(false)
				_last_cook = {"g": int(d.cg), "b": int(d.cb)}
			var a := int(d.a)
			var s := int(d.s)
			var b := int(d.get("bk", 0))
			remote_presses.act += maxi(a - _last_counts.a, 0)
			remote_presses.skill += maxi(s - _last_counts.s, 0)
			remote_presses.bark += maxi(b - _last_counts.b, 0)
			_last_counts = {"a": a, "s": s, "b": b}
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
