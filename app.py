import os
import socket

import redis
from flask import Flask, request

app = Flask(__name__)


def get_redis():
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        password=os.getenv("REDIS_PASSWORD"),
        decode_responses=True,
        socket_connect_timeout=3,
        socket_timeout=3,
    )


@app.route("/")
def index():
    count = get_redis().incr("hits")
    student = os.getenv("STUDENT", "unknown")
    return f"KR2 | {student} | container {socket.gethostname()} | hits: {count}\n"


@app.route("/health")
def health():
    return "ok\n"


@app.route("/whoami")
def whoami():
    scheme = request.headers.get("X-Forwarded-Proto", "none")
    client = request.headers.get("X-Real-IP", "none")
    host = request.headers.get("Host", "none")
    return f"scheme: {scheme}\nclient: {client}\nhost: {host}\n"
