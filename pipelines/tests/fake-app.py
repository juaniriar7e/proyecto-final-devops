#!/usr/bin/env python3
"""Servidor HTTP local que imita ALB + backend + frontend para las pruebas.
Uso: fake-app.py <puerto_archivo> <version> [--fail-patch]"""
import json, sys, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = sys.argv[2]
FAIL_PATCH = "--fail-patch" in sys.argv
TASKS = {}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")
    def do_GET(self):
        p = self.path
        if p == "/": return self.send(200, {"page": "index"})
        if p == "/api/health": return self.send(200, {"status": "ok"})
        if p == "/api/version": return self.send(200, {"version": VERSION, "service": "backend"})
        if p == "/version.json": return self.send(200, {"version": VERSION})
        if p == "/api/tasks": return self.send(200, list(TASKS.values()))
        self.send(404, {"detail": "no"})
    def do_POST(self):
        if self.path != "/api/tasks": return self.send(404)
        t = {"id": uuid.uuid4().hex, "title": self.body().get("title", ""), "done": False}
        TASKS[t["id"]] = t
        self.send(201, t)
    def do_PATCH(self):
        if FAIL_PATCH: return self.send(500, {"detail": "fallo simulado"})
        tid = self.path.rsplit("/", 1)[-1]
        if tid not in TASKS: return self.send(404)
        TASKS[tid].update(self.body()); self.send(200, TASKS[tid])
    def do_DELETE(self):
        tid = self.path.rsplit("/", 1)[-1]
        if TASKS.pop(tid, None) is None: return self.send(404)
        self.send(204)

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.serve_forever()
