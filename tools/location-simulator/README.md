# Location Simulator

This is an **independent** program (not part of the OpenHarmony project build) that simulates a moving GPS position.

## Run

```bash
cd tools/location-simulator
python3 location_simulator.py --host 0.0.0.0 --port 9000 \
  --center-lat 34.0315 --center-lon 108.7620 --radius-m 120 --speed-mps 1.4
```

Test locally:

```bash
curl -s http://127.0.0.1:9000/location
```

## Connect the phone/emulator

In the app: **个人中心 → 定位测试（模拟运动）**

- Enable 模拟定位
- Set URL to: `http://<your-PC-LAN-IP>:9000/location`

Notes:
- `127.0.0.1` on the phone refers to the **phone itself**, not your PC.
- Make sure the PC firewall allows inbound TCP on port `9000`.
