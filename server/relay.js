// HOT 'DOG' 중계 서버: 방 코드로 두 사람을 짝지어 주고, 서로의 메시지를 그대로 전달한다.
// 게임 진행은 방장(host) 쪽에서 한다. 이 서버는 전달만 한다.
//
// 보내는 것:  {t:"host"}  → {t:"room", code}      방 만들기
//            {t:"join", code} → 둘 다 {t:"paired"}  방 들어가기
// 짝이 된 뒤에는 무엇이든 상대에게 그대로 전달. 한쪽이 나가면 상대에게 {t:"left"}.
const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const FIXED = process.env.ROOM_FIXED || "";   // 테스트용: 방 코드를 고정
const rooms = new Map();                        // code -> {host, guest}

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("hotdog relay ok\n");
});
const wss = new WebSocketServer({ server });

function send(ws, obj) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
}

function newCode() {
  if (FIXED) return FIXED;
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";  // 헷갈리는 I, O 제외
  let code;
  do {
    code = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join("");
  } while (rooms.has(code));
  return code;
}

wss.on("connection", (ws) => {
  ws.alive = true;
  ws.on("pong", () => (ws.alive = true));

  ws.on("message", (data, isBinary) => {
    if (ws.peer) {
      if (ws.peer.readyState === 1) ws.peer.send(data, { binary: isBinary });
      return;
    }
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    if (msg.t === "host") {
      const code = newCode();
      rooms.set(code, { host: ws, guest: null });
      ws.room = code;
      send(ws, { t: "room", code });
    } else if (msg.t === "join") {
      const code = String(msg.code || "").toUpperCase().trim();
      const room = rooms.get(code);
      if (!room) return send(ws, { t: "error", msg: "그런 방이 없어요. 코드를 다시 확인해 주세요." });
      if (room.guest) return send(ws, { t: "error", msg: "이미 두 명이 들어간 방이에요." });
      room.guest = ws;
      ws.room = code;
      ws.peer = room.host;
      room.host.peer = ws;
      send(room.host, { t: "paired" });
      send(ws, { t: "paired" });
    }
  });

  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (room && (room.host === ws || room.guest === ws)) rooms.delete(ws.room);
    if (ws.peer) {
      send(ws.peer, { t: "left" });
      ws.peer.peer = null;
    }
  });
});

// 끊긴 연결 정리
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 20000);

server.listen(PORT, () => console.log("hotdog relay on", PORT));
