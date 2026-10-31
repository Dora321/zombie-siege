#!/usr/bin/env python3
"""在真实的 wasm 里跑自测：把测试参数注入 index.html 的 args，用无头 Chromium 打开。

先导出网页版（godot --headless --path . --export-release "Web" build/web/index.html），然后：
    python3 tools/web_test.py run --fixed-fps 60 -- --maptest --seed=1
    python3 tools/web_test.py shot out.png 40 -- --bot --god --godbase --map=alley --event=night

run 模式等到自测打印结果为止，shot 模式等指定秒数后截图。控制台有脚本或着色器错误就返回非零。
"""
import functools
import http.server
import json
import pathlib
import sys
import threading
import time

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent / "build/web"
CHROMIUM_ARGS = ["--use-gl=swiftshader", "--enable-webgl", "--ignore-gpu-blocklist", "--enable-unsafe-swiftshader"]
BAD_WORDS = ("SCRIPT ERROR", "SHADER ERROR", "USER SCRIPT ERROR", "Parse Error", "ERROR:")
# 自测结束时 quit() 触发的已知噪音，玩家的网页版没有退出按钮
IGNORED = ("reading 'currentTime'",)
RUN_TIMEOUT = 1500


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def serve() -> str:
    handler = functools.partial(QuietHandler, directory=str(ROOT))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}/"


def open_game(pw, url: str, godot_args: list, lines: list):
    browser = pw.chromium.launch(args=CHROMIUM_ARGS)
    page = browser.new_page(viewport={"width": 960, "height": 540})

    def inject(route):
        body = route.fetch().text()
        assert '"args":[]' in body, "index.html 里没找到 args"
        route.fulfill(body=body.replace('"args":[]', '"args":' + json.dumps(godot_args)), content_type="text/html")

    page.route("**/", inject)
    page.on("console", lambda m: lines.append(m.text))
    page.on("pageerror", lambda e: lines.append(f"ERROR: {e}"))
    page.goto(url)
    return browser, page


def errors(lines: list) -> list:
    return [t for t in lines if any(w in t for w in BAD_WORDS) and not any(i in t for i in IGNORED)]


def run(godot_args: list) -> int:
    lines: list = []
    with sync_playwright() as pw:
        browser, _page = open_game(pw, serve(), godot_args, lines)
        deadline = time.time() + RUN_TIMEOUT
        while time.time() < deadline and not any(("校验 " in t and "项" in t) or "[bot] 结束" in t for t in lines):
            _page.wait_for_timeout(1000)
        _page.wait_for_timeout(1500)
        browser.close()
    for t in lines:
        if "FAIL" in t or "校验 " in t or "[bot]" in t or "失败" in t:
            print(t)
    bad = errors(lines)
    for t in bad[:20]:
        print("控制台错误:", t)
    finished = any(("校验 " in t and "失败 0 项" in t) or "[bot] 结束" in t for t in lines)
    print(f"wasm 结果: {'通过' if finished and not bad else '失败'}，控制台 {len(lines)} 行，错误 {len(bad)} 行")
    return 0 if finished and not bad else 1


def shot(out: str, seconds: float, godot_args: list) -> int:
    lines: list = []
    with sync_playwright() as pw:
        browser, page = open_game(pw, serve(), godot_args, lines)
        page.wait_for_selector("#status", state="hidden", timeout=120000)
        page.wait_for_timeout(int(seconds * 1000))
        page.screenshot(path=out)
        browser.close()
    bad = errors(lines)
    for t in bad[:20]:
        print("控制台错误:", t)
    print(out, "错误", len(bad))
    return 1 if bad else 0


def main() -> int:
    if sys.argv[1] == "run":
        return run(sys.argv[2:])
    return shot(sys.argv[2], float(sys.argv[3]), sys.argv[4:])


if __name__ == "__main__":
    sys.exit(main())
