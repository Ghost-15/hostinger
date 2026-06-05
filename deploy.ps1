[CmdletBinding()]
param(
    [string]$Port = "",
    [int]$Baud = 115200
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
        return @{
            Command = 'py'
            Arguments = @('-3')
        }
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @{
            Command = 'python'
            Arguments = @()
        }
    }

    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return @{
            Command = 'python3'
            Arguments = @()
        }
    }

    throw "Aucun interpréteur Python trouvé. Installe Python ou active l'alias 'py'."
}

function Start-PortForwards {
    $services = @(
        @{ Name = 'WP Multisite'; Command = 'kubectl port-forward svc/multisite-svc 8080:80' },
        @{ Name = 'WordPress';    Command = 'kubectl port-forward svc/wordpress-svc 8081:80' },
        @{ Name = 'NodeJS';       Command = 'kubectl port-forward svc/nodejs-svc 8082:3000' },
        @{ Name = 'Debian SSH';   Command = 'kubectl port-forward svc/debian-vps-svc 2222:2222' }
    )

    Write-Host ""
    Write-Host "=== Lancement des port-forwards ===" -ForegroundColor Cyan

    foreach ($service in $services) {
        $windowCommand = @"
Write-Host '=== Port-forward $($service.Name) ===' -ForegroundColor Green
Write-Host 'Commande: $($service.Command)' -ForegroundColor Yellow
$($service.Command)
"@

        Start-Process -FilePath powershell -ArgumentList @(
            '-NoExit',
            '-ExecutionPolicy', 'Bypass',
            '-Command',
            $windowCommand
        ) | Out-Null
    }

    Write-Host '4 fenêtres de port-forward ont été ouvertes.' -ForegroundColor Green
}

Write-Host "=== Initialisation Terraform ===" -ForegroundColor Cyan
Invoke-NativeCommand -Command 'terraform' -Arguments @('init', '-upgrade')

Write-Host ""
Write-Host "=== Déploiement des microservices ===" -ForegroundColor Cyan
Invoke-NativeCommand -Command 'terraform' -Arguments @('apply', '-auto-approve')

Start-PortForwards

Write-Host ""
Write-Host "=== Envoi du mot de passe SSH sur l'ESP32 ===" -ForegroundColor Cyan

$python = Get-PythonLauncher
$pythonArgs = @()
$pythonArgs += $python.Arguments
$pythonArgs += 'esp32_send_password.py'

if ($Port) {
    $pythonArgs += '--port'
    $pythonArgs += $Port
}

$pythonArgs += '--baud'
$pythonArgs += "$Baud"

Invoke-NativeCommand -Command $python.Command -Arguments $pythonArgs

Write-Host ""
Write-Host "=== Déploiement terminé ===" -ForegroundColor Green
Write-Host "Le mot de passe SSH est affiché sur l'écran de l'ESP32."
Write-Host "Connexion: ssh admin@localhost -p 2222"