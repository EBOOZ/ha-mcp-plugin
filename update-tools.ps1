# update-tools.ps1 - refreshes src/tools/ha-cowork-tools.json from your own ha-mcp server
# Usage: .\update-tools.ps1          (uses webhookUrl from config.json)
#        .\update-tools.ps1 -Url ... (override, e.g. for testing another server)
#
# Optional step: only needed when your ha-mcp version differs from the shipped file,
# when the build reports "chatTools not found", or when Chat tool calls fail after an update.

#Requires -Version 7
param([string]$Url)

$ErrorActionPreference = "Stop"
$root      = $PSScriptRoot
$toolsPath = Join-Path $root "src/tools/ha-cowork-tools.json"
$utf8      = New-Object System.Text.UTF8Encoding($false)

# --- Config ------------------------------------------------------------------
$config = Get-Content (Join-Path $root "config.json") -Raw | ConvertFrom-Json
if (-not $Url) {
    $Url = $config.webhookUrl
    if ($Url -notmatch '^https://[^/\s<>]+/api/webhook/[^/\s<>]+$') {
        throw "config.json: webhookUrl must look like https://<domain>/api/webhook/<id> (got '$Url')"
    }
}

# --- MCP helpers -------------------------------------------------------------
$baseHeaders = @{ "Accept" = "application/json, text/event-stream" }

function Invoke-Mcp($body, $sessionId) {
    $headers = $baseHeaders.Clone()
    if ($sessionId) { $headers["Mcp-Session-Id"] = $sessionId }
    Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" `
        -Headers $headers -Body ($body | ConvertTo-Json -Depth 20 -Compress)
}

function Read-Mcp($response) {
    $text = [string]$response.Content
    if ("$($response.Headers['Content-Type'])" -like "*event-stream*") {
        $text = ($text -split "`n" | Where-Object { $_ -like "data:*" } |
                 ForEach-Object { $_.Substring(5).Trim() }) | Select-Object -Last 1
    }
    $json = $text | ConvertFrom-Json -Depth 100
    if ($json.error) { throw "MCP error $($json.error.code): $($json.error.message)" }
    $json
}

# --- Handshake and tools/list ------------------------------------------------
Write-Host "Connecting to ha-mcp..."
$init = Invoke-Mcp @{ jsonrpc = "2.0"; id = 1; method = "initialize"; params = @{
    protocolVersion = "2025-06-18"; capabilities = @{}
    clientInfo      = @{ name = "update-tools"; version = "1.0" } } }
$server    = (Read-Mcp $init).result.serverInfo
$sessionId = $init.Headers["Mcp-Session-Id"] | Select-Object -First 1
Invoke-Mcp @{ jsonrpc = "2.0"; method = "notifications/initialized" } $sessionId | Out-Null

$tools = @(); $cursor = $null; $id = 2
do {
    $params = @{}; if ($cursor) { $params.cursor = $cursor }
    $res = Read-Mcp (Invoke-Mcp @{ jsonrpc = "2.0"; id = $id; method = "tools/list"; params = $params } $sessionId)
    $tools += $res.result.tools
    $cursor = $res.result.nextCursor; $id++
} while ($cursor)

if ($tools.Count -eq 0) { throw "Server returned no tools; existing file left unchanged." }

# --- Compare with the current file -------------------------------------------
$oldNames = @()
if (Test-Path $toolsPath) {
    $oldNames = @((Get-Content $toolsPath -Raw | ConvertFrom-Json -Depth 100).tools.name)
    Copy-Item $toolsPath "$toolsPath.bak" -Force
}
$newNames = @($tools.name)
$added    = @($newNames | Where-Object { $oldNames -notcontains $_ })
$removed  = @($oldNames | Where-Object { $newNames -notcontains $_ })

New-Item -ItemType Directory -Force (Split-Path $toolsPath) | Out-Null
[IO.File]::WriteAllText($toolsPath, (@{ tools = $tools } | ConvertTo-Json -Depth 100), $utf8)

# --- Report ------------------------------------------------------------------
Write-Host "Updated src/tools/ha-cowork-tools.json" -ForegroundColor Green
if ($server) { Write-Host "  server:  $($server.name) $($server.version)" }
Write-Host "  tools:   $($newNames.Count) (was $($oldNames.Count))"
if ($added.Count)   { Write-Host "  added:   $($added -join ', ')" }
if ($removed.Count) { Write-Host "  removed: $($removed -join ', ')" -ForegroundColor Yellow }
if (Test-Path "$toolsPath.bak") { Write-Host "  backup:  src/tools/ha-cowork-tools.json.bak" }

$missing = @($config.chatTools | Where-Object { $newNames -notcontains $_ })
if ($missing.Count) {
    Write-Host "  WARNING: chatTools not on this server: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "  Fix chatTools in config.json before running build.ps1." -ForegroundColor Yellow
}
Write-Host "Next: raise version in config.json and run .\build.ps1"
