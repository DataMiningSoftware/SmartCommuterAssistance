# Smart Commuter Backend

## Quick Start (Windows / PowerShell)

```powershell
cd backend
.\run_backend.ps1
```

Server will start at:
- `http://127.0.0.1:8000`
- `http://0.0.0.0:8000`

Health check:
- `http://127.0.0.1:8000/health`

Swagger docs:
- `http://127.0.0.1:8000/docs`

## API used by Flutter

`GET /plan-trip`

Query params:
- `origin` string
- `destination` string
- `departure` ISO datetime string
- `maxRoutes` int (1..6)

Example:
```text
http://127.0.0.1:8000/plan-trip?origin=KL%20Sentral&destination=Kajang&departure=2026-03-02T10:00:00&maxRoutes=4
```

## Flutter connection notes

- Android emulator uses host loopback: `http://10.0.2.2:8000`
- iOS simulator uses: `http://127.0.0.1:8000`
- Physical phone should use your PC LAN IP, e.g. `http://192.168.1.5:8000`
