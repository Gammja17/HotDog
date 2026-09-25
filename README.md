# HOT 'DOG' — 들키면 먹힌다

핫도그 트럭 사장님 vs 핫도그로 변장한 강아지. Godot 4.7, 로우폴리 3D 탑뷰.

## 모드
- **혼자 하기: 셰프** — 핫도그를 만들어 팔면서, 트럭에 숨어든 강아지를 찾아 잡는다. 강아지는 셰프 시야(노란 부채꼴) 안에 있을 때만 보인다.
- **혼자 하기: 강아지** — 사장님 눈을 피해 소시지 5개를 먹는다. 사장님 머리 위 `?` `?!` `!!`가 의심 정도다.
- **둘이서** — 화면을 반으로 나눠 왼쪽은 셰프, 오른쪽은 강아지.

## 조작
| | 이동 | 행동 | 스킬 |
|---|---|---|---|
| 혼자 하기 (셰프/강아지) | WASD | Space | E |
| 둘이서: 강아지 | WASD | Space 변장/나오기 | E 먹기, 숨었을 때 연타하면 꼬리 참기 |
| 둘이서: 셰프 | 방향키 | Enter | 오른쪽 Shift "누가 착한 아이지~?" |

셰프의 Space는 상황에 따라 빵 집기 → 그릴 → 소스 → 진열대에 올리기/집기 → 판매 창구에서 팔기, 그리고 바로 앞 강아지나 수상한 핫도그를 집게로 찌르기.

## 승패
- 셰프: 강아지를 잡거나, 3분 동안 버티면 승리
- 강아지: 소시지 5개를 먹거나, 별점을 0으로 만들면 승리 (먹다 남긴 핫도그를 팔면 손님이 항의한다)

## 개발용
- 맵 다시 만들기: `godot --headless --path . -s tools/build_truck.gd` → `scenes/truck.tscn`
- 행동 테스트: `godot --path . -s tools/test_actions.gd`
- AI끼리 관전/스크린샷: `godot --path . -- --play --mode=watch --speed=4 --log --shot=res://shot.png --wait=60`
- Windows 빌드: `godot --headless --path . --export-release "Windows" builds/windows/HotDog.exe`

## 에셋 (모두 CC0)
- [Kenney Food Kit](https://kenney.nl/assets/food-kit), [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit)
- [Quaternius Dog](https://poly.pizza/m/2kUk0QqpCg), [Quaternius Animated Human](https://poly.pizza/m/c3Ibh9I3udk)
