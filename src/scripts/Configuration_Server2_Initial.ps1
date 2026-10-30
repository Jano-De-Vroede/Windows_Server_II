#==========================================
# Initial configuration - server2
#==========================================

#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen netwerkconfiguratie
$ipAdres = "192.168.26.20"
$subnetMask = 24
$gateway = "192.168.26.1"
$natAdapter = "Ethernet"
$hostonlyAdapter = "Ethernet 2"

# Variabelen Active Directory
$domein = "WS26-JDV.hogent"
$domein_Netbios = "WS26-JDV"
$SecureStringPassword = (ConvertTo-SecureString "AdminWindows2627" -AsPlainText -Force)
$domeinAdmin = "jdevroede"
$adminWachtwoord = ConvertTo-SecureString "JDVAdmin26!" -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential ("$domein\$domeinAdmin", $adminWachtwoord)

# Variabelen firewall
$internNetwerk = "192.168.26.0/24"
$groep = "WS2-JDV - Firewall"

#------------------------------------------
# Configuratie firewall
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

# Toegang voor beheer configureren
Add-FwRegel "Beheer - WinRM"               TCP 5985
Add-FwRegel "Beheer - RPC Endpoint Mapper" TCP 135
Add-FwRegel "Beheer - RPC dynamisch"       TCP "49152-65535"
Add-FwRegel "Beheer - SMB"                 TCP 445

# Toegang voor verschillende rollen configureren
Add-FwRegel "DNS (TCP)" TCP 53
Add-FwRegel "DNS (UDP)" UDP 53

# Configureren Default policy
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True `
    -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -LogBlocked True -LogMaxSizeKilobytes 4096

#------------------------------------------
# Configuratie netwerkinstellingen
#------------------------------------------

Write-Host "`n=== CONFIGURATIE NETWERKINSTELLINGEN ===`n" -ForegroundColor Cyan

# Ophalen van de interface index die zal gebruikt worden voor het privé netwerk
$ifIndex = (Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $hostonlyAdapter }).InterfaceIndex

# Configuratie IP instellingen
$huidig = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

if ($huidig.IPAddress -eq $ipAdres -and $huidig.PrefixLength -eq $subnetMask) {
    Write-Host "[OK] De netwerkinstellingen werden reeds geconfigureerd" -ForegroundColor green

} else {
    Write-Host "[...] Uitschakelen DHCP" -ForegroundColor Yellow
    Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled
    Write-Host "[OK] DHCP werd uitgeschakeld" -ForegroundColor Green

    Write-Host "[...] Bestaande IP-instellingen verwijderen" -ForegroundColor Yellow
    Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Remove-NetRoute -Confirm:$false
    Write-Host "[OK] Bestaande IP-instellingen werden verwijderd" -ForegroundColor Green

    Write-Host "[...] Configureren IP-instellingen" -ForegroundColor Yellow
    New-NetIPAddress -InterfaceIndex $ifIndex `
                 -IPAddress $ipAdres `
                 -PrefixLength $subnetMask `
                 -DefaultGateway $gateway | Out-Null
    Write-Host "[OK] IP-instellingen werden geconfigureerd" -ForegroundColor Green

    Write-Host "[...] DNS instellen op server1" -ForegroundColor Yellow
    Set-DnsClientServerAddress -InterfaceAlias $hostonlyAdapter -ServerAddresses "192.168.26.10"
    Write-Host "[OK] DNS werd ingesteld op server1" -ForegroundColor Green

}

# Geef Host-only adapter een lagere metric
Write-Host "[INFO] Host-only adapter voorrang geven op NAT adapter" -ForegroundColor Yellow
Set-NetIPInterface -InterfaceAlias $hostonlyAdapter -InterfaceMetric 10 | Out-Null
Set-NetIPInterface -InterfaceAlias $natAdapter -InterfaceMetric 50 | Out-Null

# Uitschakelen DNS-registratie van de NAT-adapter
Write-Host "[INFO] DNS-registratie uitschakelen voor NAT adapter" -ForegroundColor Yellow
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
    Write-Host "[OK] Server is reeds lid van $domein" -ForegroundColor Green

} else {
    Write-Host "[...] Server wordt toegevoegd aan $domein..." -ForegroundColor Yellow
    Add-Computer -DomainName $domein -Credential $credentials -Force
    Write-Host "[INFO] Server wordt herstart`n" -ForegroundColor Yellow

}