class_name Skeam
## SKEAM(KING 동아리 게임 상점) 도전 과제. 웹판이 SKEAM 안에서 돌 때만 알린다.
## SDK 는 export_presets.cfg 의 html/head_include 가 index.html 머리에 넣는다.
## 이름과 설명은 SKEAM game.yml 에 적는다 (docs/skeam.md, id 가 같아야 한다).
## 같은 과제를 또 알려도 SKEAM 은 한 번만 센다.

## role 을 맡은 사람이 이 과제를 이뤘다. 사람이 한 것만, 이 컴퓨터 사람 몫만 알린다.
static func unlock(game: Node, id: String, role: String) -> void:
	if Session.mode == "watch":
		return
	if game.online:
		if role != game.my_role:
			if not game.guest:
				Net.send({"k": "ach", "id": id})  # 친구 몫은 친구 화면에서 알린다
			return
	elif (role == "chef" and game.chef.is_ai) or (role == "dog" and game.dog.is_ai):
		return
	send(id)

static func send(id: String) -> void:
	if Engine.has_meta("skeam_log"):
		Engine.get_meta("skeam_log").append(id)  # 테스트용
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.SKEAM && SKEAM.unlock('%s')" % id)
