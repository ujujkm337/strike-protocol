#!/usr/bin/env python3
"""Раздаёт веб-сборку Godot так, как того требует браузер.

Зачем не двойной клик по index.html:
  * file:// запрещает грузить .wasm (нет Streaming/compile без http);
  * Godot требует COOP/COEP-заголовки;
  * нужен Range/206, иначе Safari не качает pck, а прогресс-бар врёт.

Запуск:  python3 web_serve.py [--public]
  без ключей — 127.0.0.1:8060 (только эта машина);
  --public    — 0.0.0.0:8060 (доступно из локальной сети/с телефона).
"""
from __future__ import annotations

import argparse
import os
import re
import socket
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

TYPES = {
	".js": "text/javascript",
	".mjs": "text/javascript",
	".wasm": "application/wasm",
	".pck": "application/octet-stream",
	".png": "image/png",
	".svg": "image/svg+xml",
	".json": "application/json",
	".html": "text/html",
	".ico": "image/x-icon",
}


class Handler(SimpleHTTPRequestHandler):
	protocol_version = "HTTP/1.1"

	def end_headers(self) -> None:
		# Godot web: isolate origin + cross-origin-embedder, иначе SharedArrayBuffer
		# (потоки) недоступны. Работаем и без него (thread_support=false), но
		# без COEP браузер иногда режет загрузку pck.
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		self.send_header("Accept-Ranges", "bytes")
		self.send_header("Cache-Control", "no-store")
		super().end_headers()

	def guess_type(self, path: str) -> str:
		ext = os.path.splitext(path)[1].lower()
		return TYPES.get(ext, super().guess_type(path))

	def send_head(self):
		"""Range -> 206: прогресс-бар загрузки pck/wasm и Safari."""
		rng = self.headers.get("Range")
		path = self.translate_path(self.path)
		if not rng or not os.path.isfile(path):
			return super().send_head()
		m = re.match(r"bytes=(\d*)-(\d*)", rng)
		if not m:
			return super().send_head()
		size = os.path.getsize(path)
		start = int(m.group(1) or 0)
		end = int(m.group(2)) if m.group(2) else size - 1
		end = min(end, size - 1)
		if start > end or start >= size:
			self.send_error(416, "Requested Range Not Satisfiable")
			self.send_header("Content-Range", f"bytes */{size}")
			return None
		try:
			f = open(path, "rb")
		except OSError:
			self.send_error(404, "File not found")
			return None
		f.seek(start)
		length = end - start + 1
		self.send_response(206)
		self.send_header("Content-Type", self.guess_type(path))
		self.send_header("Content-Length", str(length))
		self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
		self.end_headers()
		return f

	def log_message(self, fmt: str, *args) -> None:
		sys.stderr.write("  %s\n" % (fmt % args))

	def handle(self) -> None:
		try:
			super().handle()
		except (ConnectionResetError, BrokenPipeError):
			pass

	def finish(self) -> None:
		try:
			super().finish()
		except (ConnectionResetError, BrokenPipeError):
			pass


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--public", action="store_true", help="слушать 0.0.0.0 вместо 127.0.0.1")
	ap.add_argument("--port", type=int, default=8060)
	args = ap.parse_args()

	root = os.path.dirname(os.path.abspath(__file__))
	need = ("index.html", "index.js", "index.wasm", "index.pck")
	miss = [f for f in need if not os.path.isfile(os.path.join(root, f))]
	if miss:
		print(f"  нет файлов сборки в {root}: {', '.join(miss)}")
		print("  распакуй strike-protocol-web.zip и запусти serve.py из папки web/")
		return 1

	handler = partial(Handler, directory=root)
	host = "0.0.0.0" if args.public else "127.0.0.1"
	with ThreadingHTTPServer((host, args.port), handler) as httpd:
		shown = host
		if host == "0.0.0.0":
			try:
				s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
				s.connect(("8.8.8.8", 80))
				shown = s.getsockname()[0]
				s.close()
			except OSError:
				pass
		print(f"  веб-сборка: http://{shown}:{args.port}  (папка {root})")
		print("  Ctrl+C — остановить. Первый заход качает ~70 МБ (wasm+pck).")
		try:
			httpd.serve_forever()
		except KeyboardInterrupt:
			print("\n  остановлено")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
