# Copy and paste this entire block into PowerShell on the Hyper-V VM

Write-Host "Configuring PSRemoting..." -ForegroundColor Cyan

# Enable PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Configure TrustedHosts
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

# Restart WinRM
Restart-Service WinRM -Force

# Test locally
Write-Host "`nTesting PSRemoting locally..." -ForegroundColor Cyan
Test-WSMan localhost

# Show listeners
Write-Host "`nWinRM Listeners:" -ForegroundColor Cyan
Get-WSManInstance -ResourceURI winrm/config/listener -Enumerate | Format-List

# Show service status
Write-Host "`nWinRM Service Status:" -ForegroundColor Cyan
Get-Service WinRM | Format-List

Write-Host "`n✅ PSRemoting configuration completed!" -ForegroundColor Green
Write-Host "You can now test from your local machine with:" -ForegroundColor Yellow
Write-Host "Test-NetConnection -ComputerName 132.196.101.211 -Port 5985" -ForegroundColor White
