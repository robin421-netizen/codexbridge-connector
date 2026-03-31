# CodexBridge Connector

One-shot bootstrap scripts for connecting a personal computer to CodexBridge mobile app.

## Files

- `connect.sh` for macOS/Linux terminal
- `connect.ps1` for Windows PowerShell
- `SHA256SUMS` checksums for the scripts

## Usage

### macOS

```bash
/bin/bash -lc "$(curl -fsSL https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/codexbridge-connector/main/connect.sh)" -- --pair-code <PAIR_CODE> --expires 600
```

### Windows (PowerShell)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/codexbridge-connector/main/connect.ps1 -UseBasicParsing | iex; Start-CodexBridgeConnect -PairCode '<PAIR_CODE>' -Expires 600"
```

## What it does

1. Starts local `codex app-server` on `127.0.0.1:4500`.
2. Opens a public tunnel using `cloudflared` (preferred) or `ngrok`.
3. Prints `pair_code` + `ws_url` payload to be consumed by mobile scanner.

## Requirements

- `codex` installed and authenticated on the computer.
- Either `cloudflared` or `ngrok` installed.

