# SKEAM 도전 과제

SKEAM(KING 동아리의 게임 상점, https://kh32-7.github.io/skeam/)에 웹판을 올리면, 게임 안에서 이룬 도전 과제가 SKEAM 에 뜬다.

## 어떻게 도나

- `export_presets.cfg` 의 웹 설정 `html/head_include` 가 index.html 머리에 SKEAM SDK(`skeam-sdk.js`)를 넣는다.
- 과제를 이루는 순간 `Skeam.unlock(game, id, 역할)` 을 부른다 (`scripts/skeam.gd`).
  - 사람이 한 일만 센다. AI 가 한 일, AI끼리 관전(watch)은 세지 않는다.
  - 온라인에서는 게임이 방장 쪽에서 돈다. 친구 몫 과제는 방장이 친구에게 보내고, 친구 화면에서 알린다.
  - SKEAM 밖(Pages 주소로 바로 할 때 · 편집기 · PC판)에서는 아무 일도 하지 않는다.
  - 같은 과제를 또 알려도 SKEAM 은 한 번만 센다. 등록하지 않은 id 는 SKEAM 이 무시한다.
- 과제를 더하려면 부를 곳에 `Skeam.unlock` 한 줄, 아래 목록에 한 줄을 넣고 SKEAM 에 다시 등록한다. id 는 둘이 같아야 한다.

## SKEAM 에 등록할 목록

SKEAM `games/<게임 id>/game.yml` 의 `achievements:` 에 그대로 넣는다 (아이콘은 없어도 된다. 없으면 🏆 가 뜬다).

```yaml
achievements:
  # 셰프
  - id: first_sale
    name: "개업 첫 손님"
    desc: "셰프로 핫도그를 처음 파세요"
  - id: perfect_cook
    name: "불 조절의 달인"
    desc: "바늘이 초록 칸일 때 눌러 소시지를 뒤집으세요"
  - id: caught_dog
    name: "잡았다 요놈!"
    desc: "집게로 강아지를 잡으세요"
  - id: chef_win
    name: "오늘 장사 끝"
    desc: "3분 안에 핫도그 10개를 팔아 셰프로 이기세요"
  - id: chef_flawless
    name: "별점 만점 영업"
    desc: "별점 5개 그대로 셰프로 이기세요"
  # 강아지
  - id: first_bite
    name: "첫 한 입"
    desc: "강아지로 소시지를 처음 먹으세요"
  - id: rack_hide
    name: "진열대 속 핫도그"
    desc: "진열대 빈칸에 핫도그로 변장해 숨으세요"
  - id: steal
    name: "손님 핫도그 강탈"
    desc: "장터 테이블 손님의 핫도그를 뺏어 먹으세요"
  - id: bark_scare
    name: "왈!"
    desc: "짖어서 줄 선 손님을 쫓아내세요"
  - id: dog_full
    name: "배부른 강아지"
    desc: "소시지 5개를 먹고 강아지로 이기세요"
  - id: dog_sabotage
    name: "오늘 장사 망했다"
    desc: "사장님이 목표를 못 채우게 해서 강아지로 이기세요"
  # 함께
  - id: tut_chef
    name: "수습 셰프"
    desc: "셰프 연습을 끝까지 해내세요"
  - id: tut_dog
    name: "수습 강아지"
    desc: "강아지 연습을 끝까지 해내세요"
  - id: online
    name: "친구랑 한 판"
    desc: "온라인으로 친구와 한 판을 끝까지 하세요"
```

## 확인

- 시험: `godot --headless --path . -s tools/test_skeam.gd`
- 배포한 뒤: Pages 주소에서 페이지 소스에 `skeam-sdk.js` 줄이 있는지 본다. SKEAM 에서 게임을 열고 셰프로 핫도그를 하나 팔면 "도전 과제 달성! 개업 첫 손님"이 뜬다.
