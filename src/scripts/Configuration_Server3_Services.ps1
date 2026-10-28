#==========================================
# CONFIGURATIE SERVER3 - SERVICES
#==========================================

#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen Active Directory
$domein      = "WS26-JDV.hogent"
$adminWachtwoord = ConvertTo-SecureString "JDVAdmin26!" -AsPlainText -Force
$domeinAdmin = "jdevroede"
$credentials = New-Object System.Management.Automation.PSCredential ("$domein\$domeinAdmin", $adminWachtwoord)

# Variabelen DHCP
$scopeNaam   = "ScopeClients"
$scopeId     = "192.168.26.0"
$subnetMask  = "255.255.255.0"
$eersteIP    = "192.168.26.100"
$laatsteIP   = "192.168.26.200"
$dnsServers   = @(
    "192.168.26.10",
    "192.168.26.20"
)
$domein      = "WS26-JDV.hogent"
$uisluitingStart = "192.168.26.151"

# Variabelen CA
$caNaam      = "WS26-JDV-Root-CA"
$gpoNaam = "GPO CA"
$tijdelijkPadGpo = "$env:TEMP\rootca.cer"

#------------------------------------------
# Configuratie DHCP
#------------------------------------------

Write-Host "`n=== CONFIGUREREN DHCP ===`n" -ForegroundColor Cyan

# Installeren DHCP-rol 
if (-not (Get-WindowsFeature DHCP).Installed) {
    Write-Host "[...] Installeren DHCP-rol" -ForegroundColor Yellow
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
    Write-Host "[OK] DHCP-rol is geïnstalleerd" -ForegroundColor Green

} else {
    Write-Host "[OK] DHCP-rol werd reeds geïnstalleerd" -ForegroundColor Green

}

# Aanmaken beveiligingsgroepen
Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue

# Aanmaken DHCP-scope
$bestaatScope = Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue

if (-not $bestaatScope) {
    Write-Host "[...] Aanmaken DHCP Scope '$scopeNaam'" -ForegroundColor Yellow
    Add-DhcpServerv4Scope -Name $scopeNaam -StartRange $eersteIP -EndRange $laatsteIP -SubnetMask $subnetMask -State Active
    Write-Host "[OK] DHCP Scope '$scopeNaam' is aangemaakt" -ForegroundColor Yellow

} else {
    Write-Host "[OK] DHCP Scope '$scopeNaam' bestaat al. Instellingen worden bijgewerkt" -ForegroundColor Green
    Set-DhcpServerv4Scope -ScopeId $ScopeId -Name $ScopeNaam -StartRange $eersteIP -EndRange $laatsteIP -State Active

}

# Instellen DHCP opties
Write-Host "[INFO] Instellen scope-opties" -ForegroundColor Yellow
Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsServer $dnsServers -DnsDomain $domein

# Uitsluiten IP-addressen: 192.168.26.151 - 192.168.26.200
$bestaatUitsluiting = Get-DhcpServerv4ExclusionRange -ScopeId $scopeId -ErrorAction SilentlyContinue |
    Where-Object {
        $_.StartRange -eq $uisluitingStart -and
        $_.EndRange -eq $laatsteIP

    }


if (-not $bestaatUitsluiting) {
    Write-Host "[...] Toevoegen Uitsluiting: 192.168.26.151 - 192.168.26.200" -ForegroundColor Yellow
    Add-DhcpServerv4ExclusionRange -ScopeId $scopeId -StartRange $uisluitingStart -EndRange $laatsteIP
    Write-Host "[OK] Uitsluiting 192.168.26.151 - 192.168.26.200 werd toegevoegd" -ForegroundColor Green

} else {
    Write-Host "[OK] De uitsluiting 192.168.26.151 - 192.168.26.200 bestaat reeds" -ForegroundColor Green

}

# DHCP-service starten
$service = Get-Service -Name dhcpserver -ErrorAction SilentlyContinue

if ($service.Status -ne 'Running') {
    Write-Host "[INFO] Starten DHCP service" -ForegroundColor Yellow
    Start-Service -Name dhcpserver
} else {
    Write-Host "[INFO] Herstarten DHCP service" -ForegroundColor Yellow
    Restart-Service -Name dhcpserver
}


#------------------------------------------
# Configuratie CA
#------------------------------------------

Write-Host "`n=== CONFIGUREREN CA ===`n" -ForegroundColor Cyan

# Installeren CA-rol 
$caRollen = Get-WindowsFeature ADCS-Cert-Authority, ADCS-Web-Enrollment

if ($caRollen | Where-Object { -not $_.Installed }) {
    Write-Host "[...] Installeren CA-rollen" -ForegroundColor Yellow
    Install-WindowsFeature ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools
    Write-Host "[OK] CA-rollen zijn geïnstalleerd" -ForegroundColor Green

} else {
    Write-Host "[OK] CA-rollen werden reeds geïnstalleerd" -ForegroundColor Green

}

# Configuratie CA
if (-not (Test-Path HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$caNaam)) {
    Write-Host "[...] De CA wordt geconfigureerd" -ForegroundColor Yellow
    Install-AdcsCertificationAuthority -Credential $credentials -CAType EnterpriseRootCa `
        -CACommonName $caNaam -KeyLength 4096 -HashAlgorithmName SHA256 `
        -ValidityPeriod Years -ValidityPeriodUnits 10 -Force | Out-Null
    Write-Host "[OK] De CA werd succesvol geconfigureerd" -ForegroundColor Green

} else {
    Write-Host "[OK] De CA werd reeds geconfigureerd" -ForegroundColor Green
} 

# Configuratie Web enrollment
Import-Module WebAdministration

if (-not (Get-WebApplication -Name CertSrv)) {
    Write-Host "[...] Web enrollment wordt uitgevoerd" -ForegroundColor Yellow
    Install-AdcsWebEnrollment -Force | Out-Null
    Write-Host "- [OK] Web enrollment werd succesvol uitgevoerd" -ForegroundColor Green

} else {
    Write-host "[OK] Web enrollment werd reeds uitgvoerd" -ForegroundColor Green

}

# Toelaten HTTP
Write-host "- [...] Laat HTTP toe om de CA te bereiken via de browser" -ForegroundColor Yellow
$appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
& $appcmd set config "Default Web Site/CertSrv" -section:access /sslFlags:None /commit:apphost | Out-Null
Write-Host "- [OK] /CertSrv is bereikbaar via HTTP" -ForegroundColor Green

#------------------------------------------
# Configuratie GPO - CA
#------------------------------------------

Write-Host "`n=== CONFIGUREREN GPO ===`n" -ForegroundColor Cyan

# Ophalen root certificaat
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like "CN=$caNaam*" -and $_.Subject -eq $_.Issuer } |
    Select-Object -First 1

Invoke-Command -ComputerName "server1.$domein" -Credential $credentials `
    -ArgumentList $gpoNaam, $cert.RawData -ScriptBlock {

    # Dit is de "brievenbus" op server1: de twee dingen uit -ArgumentList, op volgorde
    param($gpoNaam, $cerBytes)
    $ErrorActionPreference = 'Stop'

    Install-WindowsFeature GPMC | Out-Null

    # Certificaat tijdelijk opslaan, in de Trusted Root-store zetten en de blob uitlezen
    $pad = "$env:TEMP\rootca.cer"
    [IO.File]::WriteAllBytes($pad, $cerBytes)
    certutil -addstore -f Root $pad | Out-Null
    $thumb = (New-Object Security.Cryptography.X509Certificates.X509Certificate2 $pad).Thumbprint
    $blob  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\SystemCertificates\Root\Certificates\$thumb").Blob

    # GPO aanmaken (alleen als hij nog niet bestaat)
    if (-not (Get-GPO -Name $gpoNaam -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoNaam | Out-Null
    }

    # Certificaat en auto-enrollment in de GPO zetten
    Set-GPRegistryValue -Name $gpoNaam -ValueName Blob -Type Binary -Value $blob `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$thumb" | Out-Null
    Set-GPRegistryValue -Name $gpoNaam -ValueName AEPolicy -Type DWord -Value 7 `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment" | Out-Null

    # Koppelen aan het domein (een bestaande link geeft een fout die we negeren)
    New-GPLink -Name $gpoNaam -Target (Get-ADDomain).DistinguishedName -ErrorAction SilentlyContinue | Out-Null
}