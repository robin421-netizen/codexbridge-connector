function Start-CodexBridgeConnect {
  param(
    [Parameter(Mandatory = $true)][string]$PairCode,
    [int]$Expires = 600,
    [int]$Port = 4500
  )

  $ErrorActionPreference = 'Stop'

  function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
      throw "Required command not found: $Name"
    }
  }

  Assert-Command "codex"

  $workDir = Join-Path $env:TEMP ("codexbridge-" + $PairCode)
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
  $appLog = Join-Path $workDir "app-server.log"
  $tunLog = Join-Path $workDir "tunnel.log"

  Write-Host "[1/3] Starting codex app-server on 127.0.0.1:$Port ..."
  $appProc = Start-Process -FilePath "codex" -ArgumentList @("app-server", "--listen", "ws://127.0.0.1:$Port") -NoNewWindow -PassThru -RedirectStandardOutput $appLog -RedirectStandardError $appLog

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/readyz" -UseBasicParsing -TimeoutSec 2
      if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
    Start-Sleep -Seconds 1
  }
  if (-not $ready) {
    throw "app-server did not become ready. See $appLog"
  }

  $publicHttps = $null
  $tunProc = $null

  if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    Write-Host "[2/3] Starting cloudflared quick tunnel ..."
    $tunProc = Start-Process -FilePath "cloudflared" -ArgumentList @("tunnel", "--url", "http://127.0.0.1:$Port", "--no-autoupdate") -NoNewWindow -PassThru -RedirectStandardOutput $tunLog -RedirectStandardError $tunLog

    for ($i = 0; $i -lt 45; $i++) {
      if (Test-Path $tunLog) {
        $line = Select-String -Path $tunLog -Pattern 'https://[a-z0-9\.-]+\.trycloudflare\.com' | Select-Object -Last 1
        if ($line -and $line.Matches.Count -gt 0) {
          $publicHttps = $line.Matches[0].Value
          break
        }
      }
      Start-Sleep -Seconds 1
    }
  } elseif (Get-Command ngrok -ErrorAction SilentlyContinue) {
    Write-Host "[2/3] Starting ngrok tunnel ..."
    $tunProc = Start-Process -FilePath "ngrok" -ArgumentList @("http", "127.0.0.1:$Port", "--log=stdout") -NoNewWindow -PassThru -RedirectStandardOutput $tunLog -RedirectStandardError $tunLog

    for ($i = 0; $i -lt 45; $i++) {
      try {
        $json = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
        $t = $json.tunnels | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1
        if ($t) { $publicHttps = $t.public_url; break }
      } catch {}
      Start-Sleep -Seconds 1
    }
  } else {
    throw "No tunnel client found. Install cloudflared or ngrok."
  }

  if (-not $publicHttps) {
    throw "failed to get public tunnel URL. See $tunLog"
  }

  $publicWss = $publicHttps -replace '^https://', 'wss://'
  $generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  Write-Host "[3/3] Tunnel ready."
  Write-Host ""
  Write-Host "Pair code : $PairCode"
  Write-Host "WS URL    : $publicWss"
  Write-Host "Expires   : $Expires s"
  Write-Host ""
  Write-Host "Send this to mobile app scanner payload:"
  Write-Host "{\"pair_code\":\"$PairCode\",\"ws_url\":\"$publicWss\",\"expires_in\":$Expires,\"generated_at\":\"$generatedAt\"}"
  Write-Host ""
  Write-Host "Logs:"
  Write-Host "- app server: $appLog"
  Write-Host "- tunnel    : $tunLog"
  Write-Host ""
  Write-Host "Keep this terminal running. Press Ctrl+C to stop."

  try {
    Wait-Process -Id $appProc.Id
  } finally {
    if ($tunProc -and -not $tunProc.HasExited) {
      Stop-Process -Id $tunProc.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
