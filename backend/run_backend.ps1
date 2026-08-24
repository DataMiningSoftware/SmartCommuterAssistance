$ErrorActionPreference = "Stop"

$BackendDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $BackendDir ".env"
$EnvExample = Join-Path (Split-Path -Parent $BackendDir) ".env.example"

if (-not (Test-Path -LiteralPath $EnvFile)) {
    if (Test-Path -LiteralPath $EnvExample) {
        Copy-Item -LiteralPath $EnvExample -Destination $EnvFile
        Write-Host "Created $EnvFile from .env.example. Fill in SUPABASE_SERVICE_KEY."
    } else {
        Write-Host "WARNING: No .env or .env.example found. Supabase endpoints will fail."
    }
}

python -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install -r requirements.txt

if (-not $env:SUPABASE_SERVICE_KEY) {
    if (Test-Path -LiteralPath $EnvFile) {
        $KeyLine = Select-String -LiteralPath $EnvFile -Pattern "^\s*SUPABASE_SERVICE_KEY=(.+)$" | Select-Object -First 1
        if ($KeyLine) {
            $Value = ($KeyLine.Line -split "=", 2)[1].Trim()
            if ($Value -and $Value -ne "your-service-role-key-here") {
                $env:SUPABASE_SERVICE_KEY = $Value
            }
        }
    }
    if (-not $env:SUPABASE_SERVICE_KEY) {
        Write-Host "WARNING: SUPABASE_SERVICE_KEY is not set. Crowd/trip endpoints will fail."
    }
}

.\.venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
