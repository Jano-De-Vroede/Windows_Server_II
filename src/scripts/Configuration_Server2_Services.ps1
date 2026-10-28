#==========================================
# Configuration services - server2
#==========================================

#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen DNS
$primaireDNS = "192.168.26.10"
$forwardZone = "WS26-JDV.hogent"
$reverseZone = "26.168.192.in-addr.arpa"

#------------------------------------------
# Configuratie Secundaire DNS server
#------------------------------------------

Write-Host "`n=== CONFIGURATIE SECUNDAIRE DNS ===`n" -ForegroundColor Cyan

# Installeren DNS-rol
if (-not (Get-WindowsFeature DNS).Installed) {
    Write-Host "[...] Installeren DNS-rol" -ForegroundColor Yellow
    Install-WindowsFeature -Name DNS -IncludeManagementTools
    Write-Host "[OK] DNS-rol werd succesvol geïnstalleerd" -ForegroundColor Green

} else {
    Write-Host "[OK] DNS-rol werd reeds geïnstalleerd" -ForegroundColor Green

}

# DNS-server enkel laten luisteren op het interne IP
Write-Host "[INFO] DNS server enkel laten luisteren op intern netwerk" -ForegroundColor Yellow
dnscmd /ResetListenAddresses 192.168.26.20 | Out-Null
Write-Host "[INFO] DNS service herstarten" -ForegroundColor Yellow
Restart-Service DNS | Out-Null

# Wachten tot de DNS-service terug bereikbaar is
Write-Host "[INFO] Wachten tot DNS service herstart is" -ForegroundColor Yellow
$pogingen = 0
do {
    Start-Sleep -Seconds 3
    $pogingen++
    $zoneOk = Get-DnsServerZone -Name $forwardZone -ErrorAction SilentlyContinue

} until ($zoneOk -or $pogingen -ge 10)

# Aanmaken secundaire forward zone
if (-not (Get-DnsServerZone -Name $forwardZone -ErrorAction SilentlyContinue)) {
    Write-Host "[...] Aanmaken van de secundaire zone: $forwardZone" -ForegroundColor Yellow
    Add-DnsServerSecondaryZone -Name $forwardZone -MasterServers $primaireDNS -ZoneFile "$forwardZone.dns"
    Write-Host "[OK] Secundaire zone $forwardZone werd succesvol aangemaakt" -ForegroundColor Green

} else {
    Write-Host "[OK] Secundaire zone $forwardZone bestaat reeds" -ForegroundColor Green

}

# Aanmaken secundaire reverse zone
if (-not (Get-DnsServerZone -Name $reverseZone -ErrorAction SilentlyContinue)) {
    Write-Host "[...] Aanmaken van de secundaire zone: $reverseZone" -ForegroundColor Yellow 
    Add-DnsServerSecondaryZone -Name $reverseZone -MasterServers $primaireDNS -ZoneFile "$reverseZone.dns"
    Write-Host "[OK] Secundaire zone $reverseZone werd succesvol aangemaakt" -ForegroundColor Green

} else {
    Write-Host "[OK] Secundaire zone $reverseZone bestaat reeds" -ForegroundColor Green
}

#------------------------------------------
# Uitvoeren zonetransfer
#------------------------------------------

Write-Host "`n=== UITVOEREN ZONETRANSFER ===`n" -ForegroundColor Cyan

Start-Sleep -Seconds 10
Start-DnsServerZoneTransfer -Name $forwardZone -FullTransfer
Start-DnsServerZoneTransfer -Name $reverseZone -FullTransfer
Start-Sleep -Seconds 10

$forwardRecords = Get-DnsServerResourceRecord -ZoneName $forwardZone -ErrorAction SilentlyContinue
$reverseRecords = Get-DnsServerResourceRecord -ZoneName $reverseZone -ErrorAction SilentlyContinue

if ($forwardRecords -and $reverseRecords) {
    Write-Host "[OK] Zonetransfer succesvol uitgevoerd" -ForegroundColor Green

    $forwardRecords | Format-Table HostName, RecordType -AutoSize
    $reverseRecords | Format-Table HostName, RecordType -AutoSize
}
else {
    Write-Host "[FAIL] Geen records ontvangen via zonetransfer" -ForegroundColor Red
}