param(
    [ValidateSet('Start','Stop','Status')]
    [string]$Action = 'Start',
    [string]$RedisExe,
    [string]$Model = 'qwen2:7b',
    [switch]$WithFrontend
)

$ErrorActionPreference = 'Stop'
$backend = Join-Path $PSScriptRoot 'EchoMind'
$frontendDir = Join-Path $PSScriptRoot 'EchoMindFrontend'
$runtime = Join-Path $PSScriptRoot '.runtime/windows'
$registry = Join-Path $runtime 'processes.json'
$python = Join-Path $backend '.venv/Scripts/python.exe'
$chromaExe = Join-Path $backend '.venv/Scripts/chroma.exe'
$api = 'http://127.0.0.1:18010'
$chroma = 'http://127.0.0.1:18011'
$frontend = 'http://127.0.0.1:15174'
$ollama = 'http://127.0.0.1:11434'
$embeddingModel = 'bge-m3:latest'

function Wait-Service([string]$Url, [string]$Name, $Process) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 60) {
        try { return Invoke-RestMethod $Url -TimeoutSec 2 } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$Name did not become ready. Check $runtime/$Name.stderr.log"
}

function Stop-Owned {
    if (-not (Test-Path -LiteralPath $registry)) { return }
    $recorded = @(Get-Content -Raw -LiteralPath $registry | ConvertFrom-Json)
    for ($index = $recorded.Count - 1; $index -ge 0; $index--) {
        $record = $recorded[$index]
        $owned = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if (-not $owned -or $owned.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.started) {
            continue
        }
        if ($record.name -eq 'redis') {
            $redisCli = Join-Path (Split-Path -Parent $record.exe) 'redis-cli.exe'
            if (Test-Path -LiteralPath $redisCli) {
                & $redisCli -h 127.0.0.1 -p 16380 SHUTDOWN SAVE | Out-Null
                $null = $owned.WaitForExit(5000)
            }
        }
        if (-not $owned.HasExited) {
            & taskkill.exe /PID $owned.Id /T /F | Out-Null
            if (-not $owned.WaitForExit(5000)) { throw "Could not stop $($record.name)" }
        }
    }
    Remove-Item -LiteralPath $registry
}

function Test-Redis {
    & $python -c "import redis; assert redis.Redis(host='127.0.0.1', port=16380, socket_timeout=3).ping()"
    if ($LASTEXITCODE -ne 0) { throw 'Redis ping failed' }
}

if ($Action -eq 'Stop') { Stop-Owned; return }
if ($Action -eq 'Status') {
    Test-Redis
    Invoke-RestMethod "$chroma/api/v2/heartbeat" -TimeoutSec 3
    Invoke-RestMethod "$api/health" -TimeoutSec 3
    if ($WithFrontend) { Invoke-RestMethod "$frontend/api/health" -TimeoutSec 3 }
    return
}

if (Test-Path -LiteralPath $registry) {
    throw 'Existing process records found. Use Status or Stop before starting again.'
}
if (-not $RedisExe) { $RedisExe = (Get-Command redis-server.exe -ErrorAction SilentlyContinue).Source }
if (-not $RedisExe) { throw 'Provide the path to redis-server.exe via -RedisExe.' }
$RedisExe = (Resolve-Path -LiteralPath $RedisExe).Path
foreach ($exe in @($python, $chromaExe, $RedisExe)) {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Executable missing: $exe" }
}
if ($WithFrontend) {
    $node = (Get-Command node.exe).Source
    if (-not (Test-Path -LiteralPath (Join-Path $frontendDir 'node_modules/vite/bin/vite.js'))) {
        throw 'Frontend dependencies missing. Run npm.cmd ci in EchoMindFrontend.'
    }
}

$models = (Invoke-RestMethod "$ollama/api/tags" -TimeoutSec 4).models
foreach ($requiredModel in @($Model, $embeddingModel)) {
    if ($requiredModel -notin $models.name) { throw "Ollama model is not installed: $requiredModel" }
}

New-Item -Path $runtime -ItemType Directory -Force | Out-Null
@('bind 127.0.0.1', 'port 16380', 'appendonly yes', 'protected-mode yes') |
    Set-Content -LiteralPath (Join-Path $runtime 'redis.conf') -Encoding ascii
$settings = @{
    ANTHROPIC_API_KEY = 'ollama'
    ANTHROPIC_BASE_URL = $ollama
    ANTHROPIC_MODEL = $Model
    ECHOMIND_OLLAMA_URL = $ollama
    ECHOMIND_OLLAMA_EMBED_MODEL = $embeddingModel
    REDIS_URL = 'redis://127.0.0.1:16380/0'
    CHROMA_HOST = '127.0.0.1'
    CHROMA_PORT = '18011'
    CHROMA_PERSIST_DIRECTORY = (Join-Path $runtime 'fallback-chroma')
    ANONYMIZED_TELEMETRY = 'False'
    ALERT_WEBHOOK_URL = ''
    PROMETHEUS_PORT = '0'
    EVAL_BASELINE_PATH = (Join-Path $runtime 'eval/baseline.json')
    ECHOMIND_SKILLS_DIR = (Join-Path $backend 'skills')
    PYTHONUTF8 = '1'
    API_PROXY_TARGET = $api
}
$previousEnv = @{}

$started = [System.Collections.Generic.List[object]]::new()
function Start-Component([string]$Name, [string]$Exe, [string]$Arguments, [string]$Directory) {
    $process = Start-Process -FilePath $Exe -ArgumentList $Arguments -WorkingDirectory $Directory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtime "$Name.stdout.log") `
        -RedirectStandardError (Join-Path $runtime "$Name.stderr.log")
    $started.Add(@{name=$Name; exe=$Exe; pid=$process.Id; started=$process.StartTime.ToUniversalTime().Ticks.ToString()})
    ConvertTo-Json -InputObject @($started.ToArray()) | Set-Content -LiteralPath $registry
    return $process
}

try {
    foreach ($name in $settings.Keys) {
        $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
    }
    $null = Start-Component 'redis' $RedisExe 'redis.conf' $runtime
    $chromaProcess = Start-Component 'chroma' $chromaExe 'run --path chroma --host 127.0.0.1 --port 18011' $runtime
    $null = Wait-Service "$chroma/api/v2/heartbeat" 'chroma' $chromaProcess
    Test-Redis
    $apiProcess = Start-Component 'api' $python '-m uvicorn api.main:app --host 127.0.0.1 --port 18010' $backend
    $null = Wait-Service "$api/health" 'api' $apiProcess
    "EchoMind ready at $api/docs"
    if ($WithFrontend) {
        $webProcess = Start-Component 'frontend' $node 'node_modules/vite/bin/vite.js --host 127.0.0.1 --port 15174 --strictPort' $frontendDir
        $null = Wait-Service "$frontend/api/health" 'frontend' $webProcess
        "EchoMind frontend ready at $frontend"
    }
} catch {
    Stop-Owned
    throw
} finally {
    foreach ($name in $previousEnv.Keys) {
        if ($null -eq $previousEnv[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $previousEnv[$name], 'Process')
        }
    }
}
