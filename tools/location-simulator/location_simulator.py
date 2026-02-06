#!/usr/bin/env python3
"""Location Simulator (independent of the OH app)

Serves a simple HTTP endpoint that returns a moving GPS location.

- GET /location -> {"lat": <float>, "lon": <float>, "speed_mps": <float>, "ts": <ms>}

This is meant to be used by the ArkTS client when "模拟定位" is enabled.

Run:
  python3 location_simulator.py --host 0.0.0.0 --port 9000 \
    --center-lat 34.0315 --center-lon 108.7620 --radius-m 120 --speed-mps 1.4

Then set the phone-side URL to:
  http://<your-PC-LAN-IP>:9000/location
"""

from __future__ import annotations

import argparse
import json
import math
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Tuple


def meters_to_deg_lat(m: float) -> float:
    return m / 111_320.0


def meters_to_deg_lon(m: float, lat_deg: float) -> float:
    return m / (111_320.0 * math.cos(math.radians(lat_deg)) + 1e-9)


def circle_position(center_lat: float, center_lon: float, radius_m: float, speed_mps: float, t0: float) -> Tuple[float, float]:
    # circumference (meters)
    circumference = 2.0 * math.pi * max(radius_m, 1.0)
    period_s = circumference / max(speed_mps, 0.1)
    phase = ((time.time() - t0) % period_s) / period_s
    theta = phase * 2.0 * math.pi

    # Tangential motion around center.
    d_north = math.cos(theta) * radius_m
    d_east = math.sin(theta) * radius_m

    # Add small jitter to emulate GPS noise.
    jitter_n = random.uniform(-1.5, 1.5)
    jitter_e = random.uniform(-1.5, 1.5)
    d_north += jitter_n
    d_east += jitter_e

    lat = center_lat + meters_to_deg_lat(d_north)
    lon = center_lon + meters_to_deg_lon(d_east, center_lat)
    return lat, lon


class Simulator:
    def __init__(self, center_lat: float, center_lon: float, radius_m: float, speed_mps: float):
        self.center_lat = center_lat
        self.center_lon = center_lon
        self.radius_m = radius_m
        self.speed_mps = speed_mps
        self.t0 = time.time()

    def current_payload(self) -> dict:
        lat, lon = circle_position(self.center_lat, self.center_lon, self.radius_m, self.speed_mps, self.t0)
        return {
            "lat": lat,
            "lon": lon,
            "speed_mps": self.speed_mps,
            "ts": int(time.time() * 1000),
        }


def make_handler(sim: Simulator):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path.split("?")[0] != "/location":
                self.send_response(404)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"{\"error\":\"not found\"}")
                return

            payload = sim.current_payload()
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args) -> None:  # noqa: A002
            # quiet by default
            return

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description="Simple moving-location HTTP server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--center-lat", type=float, default=34.0315)
    parser.add_argument("--center-lon", type=float, default=108.7620)
    parser.add_argument("--radius-m", type=float, default=120.0)
    parser.add_argument("--speed-mps", type=float, default=1.4)
    args = parser.parse_args()

    sim = Simulator(args.center_lat, args.center_lon, args.radius_m, args.speed_mps)
    server = HTTPServer((args.host, args.port), make_handler(sim))
    print(f"Location simulator listening on http://{args.host}:{args.port}/location")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
