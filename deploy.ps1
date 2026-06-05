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
    Write-Host ""
    Write-Host "=== Lancement des port-forwards ===" -ForegroundColor Cyan

    # Récupère les commandes port-forward dynamiquement depuis les outputs Terraform
    $outputNames = @('wordpress_port_forwards', 'multisite_port_forwards', 'nodejs_port_forwards', 'vps_port_forwards')
    $commands = @()

    foreach ($outputName in $outputNames) {
        try {
            $json = terraform output -json $outputName 2>$null | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) {
                # Garde uniquement la partie avant le # (commentaire)
                $cmd = $prop.Value -split '#' | Select-Object -First 1
                $cmd = $cmd.Trim()
                $label = $prop.Name
                $commands += @{ Name = $label; Command = $cmd }
            }
        } catch { }
    }

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
            '-NoExit',
            '-ExecutionPolicy', 'Bypass',
            '-Command',
            $windowCommand
        ) | Out-Null
    }

    Write-Host "$($commands.Count) fenêtre(s) de port-forward ouvertes." -ForegroundColor Green
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
Write-Host ""
Write-Host "Connexions SSH disponibles :" -ForegroundColor Cyan
try {
    $vpsOutputs = terraform output -json vps_port_forwards 2>$null | ConvertFrom-Json
    foreach ($prop in $vpsOutputs.PSObject.Properties) {
        $sshInfo = ($prop.Value -split '#' | Select-Object -Last 1).Trim()
        Write-Host "  $($prop.Name) -> $sshInfo" -ForegroundColor Yellow
    }
} catch { }