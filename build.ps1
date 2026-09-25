# build.ps1 - builds ha-mcp-plugin.zip from .\src and .\config.json
# Usage: .\build.ps1
#
# Generated at build time (do not put these in src):
#   ai-plugin.json            Copilot Chat action, pinned to config.chatTools
#   tools/ha-chat-tools.json  subset of tools/home-assistant-tools.json

#Requires -Version 7

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$src   = Join-Path $root "src"
$build = Join-Path $root "build"
$zip   = Join-Path $root "ha-mcp-plugin.zip"
$utf8  = New-Object System.Text.UTF8Encoding($false)

function Write-Json($path, $obj) {
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 100), $utf8)
}

# --- Config ------------------------------------------------------------------
$configPath = Join-Path $root "config.json"
if (-not (Test-Path $configPath)) { throw "config.json not found. Copy config.example.json to config.json and fill it in." }
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if ($config.webhookUrl -notmatch '^https://[^/\s<>]+/api/webhook/[^/\s<>]+$') {
    throw "config.json: webhookUrl must look like https://<domain>/api/webhook/<id> (got '$($config.webhookUrl)')"
}
if ($config.version -notmatch '^\d+\.\d+\.\d+$') {
    throw "config.json: version must look like 1.0.4 (got '$($config.version)')"
}
$chatTools = @($config.chatTools)
if ($chatTools.Count -eq 0) { throw "config.json: chatTools must list at least one tool name" }

# --- Required source files ---------------------------------------------------
foreach ($f in "manifest.json", "declarativeAgent.json", "color.png", "outline.png", "tools/ha-cowork-tools.json") {
    if (-not (Test-Path (Join-Path $src $f))) { throw "Missing src/$f" }
}

# --- Fresh copy of src -------------------------------------------------------
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
Copy-Item $src $build -Recurse

# --- Generate Chat tool subset and ai-plugin.json ----------------------------
$allTools = (Get-Content (Join-Path $build "tools/ha-cowork-tools.json") -Raw | ConvertFrom-Json -Depth 100).tools
$selected = @($allTools | Where-Object { $chatTools -contains $_.name })
$missing  = @($chatTools | Where-Object { $allTools.name -notcontains $_ })
if ($missing.Count -gt 0) { throw "chatTools not found in ha-cowork-tools.json: $($missing -join ', ')" }

Write-Json (Join-Path $build "tools/ha-chat-tools.json") @{ tools = $selected }

$plugin = [ordered]@{
    '$schema'             = "https://developer.microsoft.com/json-schemas/copilot/plugin/v2.4/schema.json"
    schema_version        = "v2.4"
    name_for_human        = "Home Assistant"
    description_for_human = "Home Assistant via ha-mcp"
    namespace             = "homeassistant"
    functions             = @($selected | ForEach-Object {
        $d = "$($_.description)"; if ($d.Length -gt 1000) { $d = $d.Substring(0, 1000) }
        [ordered]@{ name = $_.name; description = $d }
    })
    runtimes              = @([ordered]@{
        type              = "RemoteMCPServer"
        auth              = @{ type = "None" }
        spec              = [ordered]@{
            url                  = "{{HA_WEBHOOK_URL}}"
            mcp_tool_description = @{ file = "tools/ha-chat-tools.json" }
        }
        run_for_functions = $chatTools
    })
}
Write-Json (Join-Path $build "ha-mcp-plugin.json") $plugin

# --- Fill placeholders, validate JSON ----------------------------------------
Get-ChildItem $build -Filter *.json -Recurse | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName)
    $text = $text.Replace("{{HA_WEBHOOK_URL}}", $config.webhookUrl).Replace("{{VERSION}}", $config.version)
    if ($text -match '\{\{[A-Z_]+\}\}') { throw "Unfilled placeholder in $($_.Name): $($Matches[0])" }
    try { $text | ConvertFrom-Json -Depth 100 | Out-Null } catch { throw "Invalid JSON in $($_.Name): $_" }
    [IO.File]::WriteAllText($_.FullName, $text, $utf8)
}

# --- Zip with everything at the root -----------------------------------------
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $build "*") -DestinationPath $zip

Write-Host "Built $zip" -ForegroundColor Green
Write-Host "  version:    $($config.version)"
Write-Host "  chat tools: $($chatTools -join ', ')"
