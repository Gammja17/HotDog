// 웹판 온라인 시험: 헤드리스 크롬 두 개 (방장=셰프, 손님=강아지). 무인도 버디즈 tools/web_mp_test.mjs 방식.
//   1) godot --headless --path . --export-release "Web" builds/web/index.html
//   2) builds/web 에서: python -m http.server 8766 --bind 127.0.0.1
//   3) node tools/web_online_test.mjs <화면 저장 폴더>
// 중개 서버(0.peerjs.com)에 실제로 붙으니 인터넷이 필요하다.
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";

const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const BASE = "http://127.0.0.1:8766/index.html";
const OUT = process.argv[2] || ".";
const HOST_ROLE = process.argv[3] || "chef";  // 방장 역할 (손님은 나머지)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const procs = [];

async function launch(name, port, url) {
  const dir = `${process.env.TEMP || "."}/hotdog_chrome_${name}`;
  mkdirSync(dir, { recursive: true });
  const proc = spawn(CHROME, [
    "--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${dir}`, "--window-size=1280,720",
    "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-first-run",
    "--disable-background-timer-throttling", "--disable-renderer-backgrounding", url,
  ], { stdio: "ignore" });
  procs.push(proc);
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(500);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === "page");
    } catch {}
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));
  let id = 0;
  const pending = new Map();
  const logs = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
    if (m.method === "Runtime.consoleAPICalled") logs.push(m.params.args.map((a) => a.value ?? "").join(" "));
  };
  const call = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await call("Runtime.enable");
  return {
    name, logs, call,
    async shot(file) {
      const r = await call("Page.captureScreenshot", { format: "png" });
      writeFileSync(`${OUT}/${file}`, Buffer.from(r.data, "base64"));
    },
    async key(type, code, key) {
      await call("Input.dispatchKeyEvent", { type, code, key, windowsVirtualKeyCode: key.toUpperCase().charCodeAt(0) });
    },
  };
}

async function waitLog(page, re, ms) {
  for (let t = 0; t < ms; t += 250) {
    const hit = page.logs.find((l) => re.test(l));
    if (hit) return hit;
    await sleep(250);
  }
  return null;
}

let fails = 0;
const check = (ok, what) => { console.log((ok ? "  ok   " : "  FAIL ") + what); if (!ok) fails++; };
try {
  const host = await launch("host", 9331, `${BASE}?devhost=${HOST_ROLE}`);
  const codeLine = await waitLog(host, /방 코드/, 40000);
  check(!!codeLine, "방장: 중개 서버에서 방 코드를 받는다");
  const code = codeLine ? codeLine.trim().split(/\s+/).pop() : "XXXX";
  const guest = await launch("guest", 9332, `${BASE}?join=${code}`);
  check(!!(await waitLog(guest, /연결됨/, 40000)), "손님: 초대 링크로 방장과 WebRTC 연결");
  check(!!(await waitLog(host, /연결됨/, 5000)), "방장: 손님과 연결");
  await sleep(4000);
  // 손님(강아지)이 왼쪽으로 달리고, Space를 눌러 본다
  await guest.key("keyDown", "KeyA", "a");
  await sleep(1500);
  await guest.key("keyUp", "KeyA", "a");
  await guest.key("keyDown", "Space", " ");
  await guest.key("keyUp", "Space", " ");
  check(!!(await waitLog(host, /손님 입력: act/, 5000)), "방장: 손님의 Space 입력을 받는다");
  await sleep(1500);
  await host.shot(`online_host_${HOST_ROLE}.png`);
  await guest.shot(`online_guest_${HOST_ROLE}.png`);
  const errs = [...host.logs, ...guest.logs].filter((l) => /SCRIPT ERROR|ERROR:/.test(l));
  check(errs.length === 0, "스크립트 오류 없음" + (errs.length ? ": " + errs.slice(0, 3).join(" | ") : ""));
} finally {
  for (const p of procs) p.kill();
  console.log("FAILS:", fails);
  process.exit(fails);
}
