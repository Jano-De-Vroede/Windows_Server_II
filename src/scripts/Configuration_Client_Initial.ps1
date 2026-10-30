#==========================================
# Initial configuration - client
#==========================================

#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen netwerkconfiguratie
$natAdapter = "Ethernet"
$hostonlyAdapter = "Ethernet 2"

# Variabelen Active Directory
$domein = "WS26-JDV.hogent"
$SecureStringPassword = (ConvertTo-SecureString "AdminWindows2627" -AsPlainText -Force)
$domeinAdmin = "jdevroede"
$adminWachtwoord = ConvertTo-SecureString "JDVAdmin26!" -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential ("$domein\$domeinAdmin", $adminWachtwoord)

# Variabelen Firewall
$internNetwerk = "192.168.26.0/24"
$groep = "WS2-JDV - Firewall"

#------------------------------------------
# Configuratie Firewall
#------------------------------------------

Write-Host "`n=== CONFIGURATIE FIREWALL ===`n" -ForegroundColor Cyan

# Functie: toevoegen firewall regel
function Add-FwRegel {
    param([string]$Naam, [string]$Protocol, [string]$Poort, [string[]]$Remote = $internNetwerk)
    Get-NetFirewallRule -DisplayName $Naam -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "[...] Firewallregel $naam wordt toegevoegd" -ForegroundColor Yellow
    New-NetFirewallRule -DisplayName $Naam -Group $groep -Direction Inbound -Action Allow `
        -Protocol $Protocol -LocalPort $Poort -RemoteAddress $Remote -Profile Any | Out-Null
    Write-Host "[OK] Firewallregel '$Naam'" -ForegroundColor Green
}

# Toegang SSH vanop de host via Host-only en NAT
Add-FwRegel "SSH (host + Vagrant NAT)" TCP 22 @("10.0.2.2","192.168.26.1")
Add-FwRegel "Vagrant WinRM (NAT)"      TCP 5985 @("10.0.2.2")

# Toestaan pings binnen het interne netwerk
Get-NetFirewallRule -DisplayName "Ping ICMPv4 (LAN)" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName "Ping ICMPv4 (LAN)" -Group $groep -Direction Inbound -Action Allow `
    -Protocol ICMPv4 -IcmpType 8 -RemoteAddress $internNetwerk -Profile Any | Out-Null

# Alles wat niet nodig is uitschakelen
"Delivery Optimization","mDNS" | ForEach-Object {
    Disable-NetFirewallRule -DisplayGroup $_ -ErrorAction SilentlyContinue
}

# Configureren Default policy
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True `
    -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -LogBlocked True -LogMaxSizeKilobytes 4096

#------------------------------------------
# Configuratie netwerkinstellingen
#------------------------------------------

Write-Host "`n=== INSTELLEN NETWERKINSTELLINGEN ===`n" -ForegroundColor Cyan

# Ophalen van de interface index die zal gebruikt worden voor het privé netwerk
$ifIndex = (Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $hostonlyAdapter }).InterfaceIndex

# Activeer DHCP
Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses

# Trigger DHCP-verzoek door adapter te herstarten
Get-NetAdapter -InterfaceIndex $ifIndex | Restart-NetAdapter

# Check wanneer client een geldig IP-adres heeft ontvangen
Write-Host "[...] Wachten op IP-adres van de DHCP-server" -ForegroundColor Yellow
do {
    Start-Sleep -Seconds 2
    $ipInfo = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $ip = $ipInfo.IPAddress
} until ($ip -and $ip -notlike "169.254.*")

Write-Host "[OK] IP-adres succesvol verkregen: $ip" -ForegroundColor Green


# Geef Host-only adapter een lagere metric
Write-Host "[INFO] Host-only adapter voorrang geven op NAT adapter" -ForegroundColor Yellow
Set-NetIPInterface -InterfaceAlias $hostonlyAdapter -InterfaceMetric 10 | Out-Null
Set-NetIPInterface -InterfaceAlias $natAdapter -InterfaceMetric 50 | Out-Null

# Uitschakelen DNS-registratie van de NAT-adapter
Set-DnsClient `
    -InterfaceAlias $natAdapter `
    -RegisterThisConnectionsAddress $false | Out-Null

Set-DnsClient `
    -InterfaceAlias $natAdapter `
    -UseSuffixWhenRegistering $false | Out-Null

Clear-DnsClientCache | Out-Null

#------------------------------------------
# Toevoeging domein
#------------------------------------------

Write-Host "`n=== TOEVOEGEN AAN DOMEIN ===`n" -ForegroundColor Cyan

# Server toevoegen aan domein
if ((Get-CimInstance Win32_ComputerSystem).Domain -eq $domein) {
    Write-Host "[OK] Client is reeds lid van $domein" -ForegroundColor Green

} else {
    Write-Host "[...] Client wordt toegevoegd aan $domein" -ForegroundColor Yellow
    Add-Computer -DomainName $domein -Credential $credentials -Restart -Force
    Write-Host "[OK] Client werd succesvol toegevoegd aan $domein`n" -ForegroundColor Green

}