#==========================================
# Configuration services - Client
#==========================================

#-------------------------------------------
# Variabelen
#-------------------------------------------

$rsatTools = @(
    "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"      # Active Directory
    "Rsat.Dns.Tools~~~~0.0.1.0"                         # DNS
    "Rsat.DHCP.Tools~~~~0.0.1.0"                        # DHCP
    "Rsat.CertificateServices.Tools~~~~0.0.1.0"         # Certification Authority
    "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"      # GPMC (GPO voor CA-vertrouwen)

)

#-------------------------------------------
# Installeren RSAT tools
#-------------------------------------------

Write-Host "`n=== INSTALLEREN RSAT-TOOLS ===`n" -ForegroundColor Cyan

foreach($tool in $rsatTools) {
    $geïnstalleerd = Get-WindowsCapability -Online -Name $tool -ErrorAction Stop

    if ($geïnstalleerd.State -eq 'Installed') {
       Write-Host "[OK] '$tool' werd reeds geïnstalleerd" -ForegroundColor Green

    } else {
        Write-Host "[...] '$tool' wordt geïnstalleerd" -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name $tool -ErrorAction Stop
        Write-Host "[OK] '$tool' werd geïnstalleerd" -ForegroundColor Green
        
    }
   
}