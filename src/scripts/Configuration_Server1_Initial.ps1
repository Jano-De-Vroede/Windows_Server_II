#==========================================
# Initial configuration - server1
#==========================================


#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen netwerkconfiguratie
$ipAdres = "192.168.26.10"
$subnetMask = 24
$gateway = "192.168.26.1"
$natAdapter = "Ethernet"
$hostonlyAdapter = "Ethernet 2"

# Variabelen Active Directory
$domein = "WS26-JDV.hogent"
$domein_Netbios = "WS26-JDV"
$SecureStringPassword = (ConvertTo-SecureString "AdminWindows2627" -AsPlainText -Force)

# Variabelen firewall
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

# Toegang voor beheer configureren
Add-FwRegel "Beheer - WinRM"               TCP 5985
Add-FwRegel "Beheer - RPC Endpoint Mapper" TCP 135
Add-FwRegel "Beheer - RPC dynamisch"       TCP "49152-65535"
Add-FwRegel "Beheer - SMB"                 TCP 445

# Toegang voor verschillende rollen configureren
Add-FwRegel "DNS (TCP)"                 TCP 53
Add-FwRegel "DNS (UDP)"                 UDP 53
Add-FwRegel "HTTP (IIS)"                TCP 80
Add-FwRegel "Kerberos (TCP)"            TCP 88
Add-FwRegel "Kerberos (UDP)"            UDP 88
Add-FwRegel "Kerberos wachtwoord (TCP)" TCP 464
Add-FwRegel "Kerberos wachtwoord (UDP)" UDP 464
Add-FwRegel "LDAP (TCP)"                TCP 389
Add-FwRegel "LDAP/CLDAP (UDP)"          UDP 389
Add-FwRegel "Global Catalog"            TCP 3268
Add-FwRegel "AD Web Services (RSAT)"    TCP 9389
Add-FwRegel "NTP / W32Time"             UDP 123

# Configureren Default policy
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True `
    -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -LogBlocked True -LogMaxSizeKilobytes 4096

#------------------------------------------
# Configuratie netwerkinstellingen
#------------------------------------------