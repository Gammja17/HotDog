# HOT 'DOG' — 들키면 먹힌다

핫도그 트럭 사장님 vs 핫도그로 변장한 강아지. Godot 4.7, 로우폴리 3D 탑뷰.

## 모드
- **온라인으로 친구랑 하기** (웹판) — 방을 만들면 4글자 코드와 초대 링크가 나온다. 브라우저끼리 WebRTC로 직접 연결하고, 처음 찾는 것만 공개 PeerJS 중개 서버를 쓴다. 방장 쪽에서 게임이 돌아간다.
- **연습하기 (셰프/강아지)** — 한 단계씩 해 보는 연습 영업. 혼자 하기를 처음 고르면 연습부터 할지 묻는다.
- **혼자 하기: 셰프** — 1인칭. 핫도그를 만들어 팔면서, 트럭에 숨어든 강아지를 찾아 잡는다. 요리하는 동안은 조리대만 보이니 등 뒤의 소리(발소리, 킁킁, 씹는 소리)를 잘 들어야 한다.
- **혼자 하기: 강아지** — 사장님 눈을 피해 소시지 5개를 먹는다. 사장님 머리 위 `?` `?!` `!!`가 의심 정도다.
- **둘이서** — 화면을 반으로 나눠 왼쪽은 셰프, 오른쪽은 강아지.

## 조작
| | 이동 | 행동 | 스킬 |
|---|---|---|---|
| 혼자 하기 (셰프/강아지) | WASD (셰프는 마우스로 둘러보기, 화면 클릭 / Esc) | Space | E |
| 강아지 | WASD | Space 변장/나오기 | E 먹기 (숨었을 때 연타하면 꼬리 참기), Q 짖기 |
| 둘이서: 셰프 | 방향키 (위아래 걷기, 좌우 돌기) | Enter | 오른쪽 Shift "누가 착한 아이지~?" |

셰프의 Space는 상황에 따라 빵 집기 → 그릴 → 소스 → 진열대에 올리기/집기 → 판매 창구에서 팔기, 그리고 바로 앞 강아지나 수상한 핫도그를 집게로 찌르기.

## 맵
트럭 안(셰프 구역)과 둘레의 장터(강아지 구역). 트럭 오른쪽 벽의 뒷문으로 드나든다.
장터에는 스탠드 테이블, 덤불, 나무, 쓰레기통, 옆 가게 천막이 있고, 바닥 핫도그가 28개 굴러다닌다.
바닥 핫도그는 흙투성이라 먹을 수 없지만 옆에 숨으면 덜 수상하다.

## 승패
- 셰프: 3분 안에 핫도그 10개를 팔면 승리 (매출로만 이긴다)
- 강아지: 소시지 5개를 먹거나, 셰프가 3분 안에 10개를 못 팔게 하거나, 별점을 0으로 만들면 승리
- 강아지를 잡으면 먹은 소시지 두 개를 뱉고 장터로 던져진다 (잠깐 어질어질하다가 다시 움직인다)
- 강아지 먹이: 진열대, 냉장고(트럭 안), 테이블에서 먹는 손님 핫도그(뺏으면 별점 -0.5), 짖어서 손님이 떨어뜨린 핫도그
- 강아지 Q 짖기: 근처 줄 선 손님이 도망가고(매출 손해), 먹던 손님은 핫도그를 떨어뜨린다. 대신 셰프에게 소리가 들린다
- 먹다 남긴 핫도그를 팔면 손님이 항의한다 (별점 -1). 멀쩡한 핫도그를 찌르면 손님들이 수군거린다 (별점 -0.5)

## 개발용
- 맵 다시 만들기: `godot --headless --path . -s tools/build_truck.gd` → `scenes/truck.tscn`
- 행동 테스트: `godot --path . -s tools/test_actions.gd`
- 조리 손맛 테스트 (연타, 초록 칸만 노리기): `godot --headless --path . -s tools/test_mash.gd`
- 손님 길찾기 테스트 (테이블을 돌아가는지, 장터 밖으로 나가는지): `godot --headless --path . -s tools/test_customer_path.gd`
- 연습(튜토리얼) 테스트: `godot --path . -s tools/test_tutorial.gd`
- 웹 빌드: `godot --headless --path . --export-release "Web" builds/web/index.html`
- 온라인 테스트 (크롬 두 개): `builds/web`에서 `python -m http.server 8766 --bind 127.0.0.1` 후 `node tools/web_online_test.mjs <화면 저장 폴더>`
- AI끼리 관전/스크린샷: `godot --path . -- --play --mode=watch --speed=4 --log --shot=res://shot.png --wait=60`
- Windows 빌드: `godot --headless --path . --export-release "Windows" builds/windows/HotDog.exe`

## 에셋
- 폰트: [도현](https://fonts.google.com/specimen/Do+Hyeon) (OFL)
- 효과음: [BigSoundBank](https://bigsoundbank.com) (CC0 실제 녹음), [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) (CC0). 자세한 목록은 `assets/sfx/CREDITS.txt`
- 3D 모델 (모두 CC0): [Kenney Nature Kit](https://kenney.nl/assets/nature-kit) (장터 나무, 덤불, 울타리, 천막)
- [Kenney Food Kit](https://kenney.nl/assets/food-kit), [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit)
- [Quaternius Dog](https://poly.pizza/m/2kUk0QqpCg), [Quaternius Animated Human](https://poly.pizza/m/c3Ibh9I3udk)
