[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Ip,

    [int]$EspPort = 80,

    [switch]$FailOnEsp32Error
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') a échoué avec le code $LASTEXITCODE."
    }
}

function Get-PythonLauncher {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        return @{ Command = 'py'; Arguments = @('-3') }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @{ Command = 'python'; Arguments = @() }
    }
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return @{ Command = 'python3'; Arguments = @() }
    }
    throw "Aucun interpréteur Python trouvé. Installe Python ou active l'alias 'py'."
}

function Start-PortForwards {
    Write-Host ""
    Write-Host "=== Lancement des port-forwards ===" -ForegroundColor Cyan

    $commands = @()
    try {
        $json = terraform output -json port_forward_commands 2>$null | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            $cmd = $prop.Value.Trim()
            $commands += @{ Name = $prop.Name; Command = $cmd }
        }
    } catch { }

    if ($commands.Count -eq 0) {
        Write-Host "Aucune commande port-forward trouvée dans les outputs Terraform." -ForegroundColor Yellow
        return
    }

    foreach ($service in $commands) {
        $windowCommand = @"
Write-Host '=== Port-forward : $($service.Name) ===' -ForegroundColor Green
Write-Host 'Commande : $($service.Command)' -ForegroundColor Yellow
$($service.Command)
"@
        Start-Process -FilePath powershell -ArgumentList @(
            '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $windowCommand
        ) | Out-Null
    }

    Write-Host "$($commands.Count) fenêtre(s) de port-forward ouvertes." -ForegroundColor Green
}

# ── Terraform ──────────────────────────────────────────────────────────────────
Write-Host "=== Initialisation Terraform ===" -ForegroundColor Cyan
Invoke-NativeCommand -Command 'terraform' -Arguments @('init', '-upgrade')

Write-Host ""
Write-Host "=== Déploiement des microservices ===" -ForegroundColor Cyan
Invoke-NativeCommand -Command 'terraform' -Arguments @('apply', '-auto-approve')

Start-PortForwards

# ── ESP32 via IP ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Envoi du mot de passe sur l'ESP32 ($Ip) ===" -ForegroundColor Cyan

$python     = Get-PythonLauncher
$pythonArgs = $python.Arguments + @('esp32_send_password.py', '--ip', $Ip, '--port', "$EspPort")

try {
    Invoke-NativeCommand -Command $python.Command -Arguments $pythonArgs
    Write-Host "Envoi ESP32 réussi." -ForegroundColor Green
}
catch {
    if ($FailOnEsp32Error) {
        throw
    }

    Write-Host "Avertissement: échec de l'envoi vers l'ESP32, mais le déploiement continue." -ForegroundColor Yellow
    Write-Host "Détail: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ── Résumé ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Déploiement terminé ===" -ForegroundColor Green
Write-Host "Le mot de passe est affiché sur l'écran de l'ESP32."
Write-Host ""
Write-Host "Connexions SSH disponibles :" -ForegroundColor Cyan
try {
    $servicesOutput = terraform output -json services 2>$null | ConvertFrom-Json
    foreach ($prop in $servicesOutput.PSObject.Properties) {
        if ($prop.Value -match 'ssh|vps') {
            Write-Host "  $($prop.Name) -> $($prop.Value)" -ForegroundColor Yellow
        }
    }
} catch { }
