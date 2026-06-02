# port-forward.ps1
# Lance les 4 port-forwards dans des fenêtres PowerShell séparées

Write-Host "Demarrage des port-forwards..." -ForegroundColor Green

$services = @(
    @{ Name = "WP Multisite"; Cmd = "kubectl port-forward svc/multisite-svc 8080:80" },
    @{ Name = "WordPress";    Cmd = "kubectl port-forward svc/wordpress-svc 8081:80" },
    @{ Name = "NodeJS";       Cmd = "kubectl port-forward svc/nodejs-svc 8082:3000" },
    @{ Name = "Debian SSH";   Cmd = "kubectl port-forward svc/debian-vps-svc 2222:22" }
)

foreach ($svc in $services) {
    Write-Host "Lancement : $($svc.Name)" -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $svc.Cmd
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "Services disponibles :" -ForegroundColor Green
Write-Host "WP Multisite : http://localhost:8080"
Write-Host "WordPress    : http://localhost:8081"
Write-Host "NodeJS       : http://localhost:8082"
Write-Host "SSH Debian   : ssh root@localhost -p 2222"
Write-Host ""
Write-Host "Mot de passe SSH : debian_root_pass" -ForegroundColor Yellow