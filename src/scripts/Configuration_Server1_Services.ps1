#==========================================
# Configuration services - server1
#==========================================

#------------------------------------------
# Variabelen
#------------------------------------------

# Variabelen OU's
$rootOU = "JDV-Industries"
$rootOUPath = "OU=$rootOU,DC=WS26-JDV,DC=hogent"
$directieOU = "Directie"
$bediendenOU = "Bedienden"
$itOU = "IT"

$OUs = @(
    $directieOU
    $bediendenOU
    $itOU
)

# Variabelen users
$userWachtwoord = ConvertTo-SecureString "JDVUser26!" -AsPlainText -Force
$adminWachtwoord = ConvertTo-SecureString "JDVAdmin26!" -AsPlainText -Force

$domainUsers = @(
    @{FirstName="Maite"; LastName="Brondeel"; Username="mbrondeel"; OU=$directieOU}
    @{FirstName="Benita"; LastName="Marcelis"; Username="bmarcelis"; OU=$bediendenOU}
    @{FirstName="Egon"; LastName="De Vroede"; Username="edevroede"; OU=$bediendenOU}
    @{FirstName="Olivier"; LastName="De Vroede"; Username="odevroede"; OU=$bediendenOU}
    @{FirstName="Yoran"; LastName="Van de Gucht"; Username="yvandegucht"; OU=$itOU}
)

$domainAdmins = @(
    @{FirstName="Jano"; LastName="De Vroede"; Username="jdevroede"; OU=$directieOU}
    @{FirstName="Ruben"; LastName="Jacobs"; Username="rjacobs"; OU=$itOU}
)

# Variabelen DNS
$forwardZone = "WS26-JDV.hogent"
$reverseZone = "26.168.192.in-addr.arpa"
$secundaireIP  = "192.168.26.20"
$secundaireDNS = "server2.WS26-JDV.hogent"

$aRecords = @(
    @{ Naam = "server2"; IP = "192.168.26.20" }
    @{ Naam = "server3"; IP = "192.168.26.30" }
)

$ptrRecords = @(
    @{ Naam = "10"; FQDN = "server1.WS26-JDV.hogent" }
    @{ Naam = "20"; FQDN = "server2.WS26-JDV.hogent" }
    @{ Naam = "30"; FQDN = "server3.WS26-JDV.hogent" }
)

# Variabelen IIS
$domein = "WS26-JDV.hogent"
$hoofdMap = "C:\inetpub\intranet"
$siteNaam = "Intranet"
$url = "intranet.$domein"
$hostRecord = "intranet"
$ptrRecord = "10"
$ipWebserver = "192.168.26.10"
$html = "C:\inetpub\wwwroot\index.html"
$inhoud = "<html><body><h1>Hello World</h1></body></html>"

# Variabelen DHCP
$adminWachtwoord = ConvertTo-SecureString "JDVAdmin26!" -AsPlainText -Force
$domeinAdmin = "jdevroede"
$credentials = New-Object System.Management.Automation.PSCredential ("$domein\$domeinAdmin", $adminWachtwoord)

#-------------------------------------------
# Configuratie OU's
#-------------------------------------------

Write-Host "`n=== AANMAKEN VAN DE OU's ===`n" -ForegroundColor cyan

# Aanmaken root OU
$rootBestaat = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$rootOUPath'" -ErrorAction SilentlyContinue

if ($rootBestaat) {
    Write-Host "[OK] De root OU $rootOU bestaat reeds" -ForegroundColor green

} else {
   Write-Host "[...] Aanmaken van de root OU: $rootOU" -ForegroundColor Yellow
   New-ADOrganizationalUnit -Name $rootOU -Path "DC=WS26-JDV,DC=hogent"
   Write-Host "[OK] De root OU $routOU werd succesvol aangemaakt" -ForegroundColor Green

}

# Aanmaken onderliggende OU's
foreach ($OU in $OUs) {
   
   $ouPath = "OU=$OU,OU=$rootOU,DC=WS26-JDV,DC=hogent"
   $bestaat =  Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue

   if ($bestaat) {
      Write-Host "[OK] De OU '$OU' bestaat reeds" -ForegroundColor Green

   } else {
      Write-Host "[...] Aanmaken van de OU:  $OU " -ForegroundColor Yellow
      New-ADOrganizationalUnit -Name $OU -Path "OU=$rootOU,DC=WS26-JDV,DC=hogent"
      Write-Host "[OK] De OU '$OU' werd succesvol aangemaakt" -ForegroundColor Green

   }
}

#-------------------------------------------
# Configuratie Users
#-------------------------------------------

Write-Host "`n=== CONFIGURATIE USERS ===`n" -ForegroundColor Cyan

# Aanmaken domain users
foreach ($user in $domainUsers) {

   $ouUserPath = "OU=$($user.OU),OU=$rootOU,DC=WS26-JDV,DC=hogent"
   $gebruikerBestaat = Get-ADUser -Filter "SamAccountName -eq '$($user.Username)'" -ErrorAction SilentlyContinue
   
   if ($gebruikerBestaat) {
       Write-Host "[OK] De gebruiker $($user.Username) bestaat reeds" -ForegroundColor Green

   } else {
      Write-Host "[...] Aanmaken van de gebruiker: $($user.Username)" -ForegroundColor Yellow

      New-ADUser `
      -Name "$($user.FirstName) $($user.LastName)" `
      -GivenName $user.FirstName `
      -Surname $user.LastName `
      -SamAccountName $user.Username `
      -UserPrincipalName "$($user.Username)@WS26-JDV.hogent" `
      -Path $ouUserPath `
      -AccountPassword $userWachtwoord `
      -Enabled $true

      Write-Host "- [OK] De gebruiker $($user.Username) werd succesvol aangemaakt" -ForegroundColor Green

   }

}

# Aanmaken domain admins
foreach ($admin in $domainAdmins) {

   $ouAdminPath = "OU=$($admin.OU),OU=$rootOU,DC=WS26-JDV,DC=hogent"
   $adminBestaat = Get-ADUser -Filter "SamAccountName -eq '$($admin.Username)'" -ErrorAction SilentlyContinue
   
   if ($adminBestaat) {
       Write-Host "[OK] De admin $($admin.Username) bestaat reeds" -ForegroundColor green

   } else {
      Write-Host "[...] Aanmaken van de admin: $($admin.Username)" -ForegroundColor Yellow

      New-ADUser `
      -Name "$($admin.FirstName) $($admin.LastName)" `
      -GivenName $admin.FirstName `
      -Surname $admin.LastName `
      -SamAccountName $admin.Username `
      -UserPrincipalName "$($admin.Username)@WS26-JDV.hogent" `
      -Path $ouAdminPath `
      -AccountPassword $adminWachtwoord `
      -Enabled $true

      Write-Host "[OK] De admin $($admin.Username) werd succesvol aangemaakt" -ForegroundColor green

      Write-Host "[...] Toegevoegen $($admin.Username) aan Domain Admins" -ForegroundColor Yellow
      Add-ADGroupMember -Identity "Domain Admins" -Members $admin.Username -ErrorAction Stop
      Write-Host "[OK] $($admin.Username) werd toegevoegd aan Domain Admins" -ForegroundColor Green

      Write-Host "- [...] Toegevoegen $($admin.Username) aan Enterprise Admins" -ForegroundColor Yellow
      Add-ADGroupMember -Identity 'Enterprise Admins' -Members $admin.Username -ErrorAction Stop
      Write-Host "[OK] $($admin.Username) werd toegevoegd aan Enterprise Admins" -ForegroundColor Green

   }

}

#-------------------------------------------
# Configuratie primaire DNS server
#-------------------------------------------

Write-Host "`n=== CONFIGUREREN PRIMAIRE DNS ===`n" -ForegroundColor Cyan

# DNS-server enkel laten luisteren op het interne IP
Write-Host "[INFO] DNS server enkel laten luisteren op intern netwerk" -ForegroundColor Yellow
dnscmd /ResetListenAddresses 192.168.26.10 | Out-Null
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

# Herstart NetLogon
Write-Host "[INFO] NetLogon herstarten" -ForegroundColor Yellow
Restart-Service Netlogon | Out-Null
nltest /dsregdns | Out-Null

# Opruimen resterende records
$zones = @("WS26-JDV.hogent", "_msdcs.WS26-JDV.hogent")

Write-Host "[INFO] Opruimen overbodige records" -ForegroundColor Yellow
foreach ($z in $zones) {
    Get-DnsServerResourceRecord -ZoneName $z -RRType A -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordData.IPv4Address.IPAddressToString -like "10.0.2.*" } |
        Remove-DnsServerResourceRecord -ZoneName $z -Force
    Get-DnsServerResourceRecord -ZoneName $z -RRType AAAA -ErrorAction SilentlyContinue |
        Remove-DnsServerResourceRecord -ZoneName $z -Force

}

# Dynamische update uitschakelen
Write-Host "[INFO] Dynamische updates uitschakelen" -ForegroundColor Yellow
Set-DnsServerPrimaryZone -Name $forwardZone -DynamicUpdate None
Set-DnsServerPrimaryZone -Name "_msdcs.$forwardZone" -DynamicUpdate None

# Toevoegen benodigde A-records
foreach ($a in $aRecords) {
    $existing = Get-DnsServerResourceRecord -ZoneName $forwardZone -Name $a.Naam -RRType A -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "[...] Toevoegen A-record: $($a.Naam) -> ($($a.IP))" -ForegroundColor Yellow
        Add-DnsServerResourceRecordA -Name $a.Naam -ZoneName $forwardZone -IPv4Address $a.IP
        Write-Host "[OK] A-record: $($a.Naam) -> ($($a.IP)) werd succesvol toegevoegd" -ForegroundColor Green

    } else {
        Write-Host "[OK] A-record $($a.Naam) bestaat reeds" -ForegroundColor Green

    }
}

# Toevoegen benodigde PTR-recors
foreach ($ptr in $ptrRecords) {
    $existingPtr = Get-DnsServerResourceRecord -ZoneName $reverseZone -Name $ptr.Naam -RRType Ptr -ErrorAction SilentlyContinue
    if (-not $existingPtr) {
        Write-Host "[...] Toevoegen PTR-record: $($ptr.Naam) -> $($ptr.FQDN) " -ForegroundColor Yellow
        Add-DnsServerResourceRecordPtr -Name $ptr.Naam -ZoneName $reverseZone -PtrDomainName $ptr.FQDN
        Write-Host "[OK] PTR-record: $($ptr.Naam) -> $($ptr.FQDN) werd succesvol toegevoegd " -ForegroundColor green

    } else {
        Write-Host "[OK] PTR-record $($ptr.Naam) bestaat reeds" -ForegroundColor green

    }
}

# Toevoegen NS records voor secundaire DNS server
$nsForward = Get-DnsServerResourceRecord -ZoneName $forwardZone -RRType NS -ErrorAction SilentlyContinue | Where-Object { $_.RecordData.NameServer -eq "$secundaireDNS." }

if (-not $nsForward) {
    Write-Host "[...] Toevoegen NS-record aan $forwardZone : $secundaireDNS" -ForegroundColor Yellow
    Add-DnsServerResourceRecord -NS -Name "@" -ZoneName $forwardZone -NameServer $secundaireDNS
    Write-Host "[OK] NS-record $secundaireDNS werd succesvol toegevoegd in $forwardZone" -ForegroundColor Green

} else {
    Write-Host "[OK] NS-record $secundaireDNS bestaat al in $forwardZone" -ForegroundColor Green

}

$nsReverse = Get-DnsServerResourceRecord -ZoneName $reverseZone -RRType NS -ErrorAction SilentlyContinue | Where-Object { $_.RecordData.NameServer -eq "$secundaireDNS." }

if (-not $nsReverse) {
    Write-Host "[...] Toevoegen NS-record aan $reverseZone : $secundaireDNS " -ForegroundColor Yellow
    Add-DnsServerResourceRecord -NS -Name "@" -ZoneName $reverseZone -NameServer $secundaireDNS
    Write-Host "[OK] NS-record $secundaireDNS werd succesvol toegvoegd in $reverseZone" -ForegroundColor Green

} else {
    Write-Host "[OK] NS-record $secundaireDNS bestaat al in $reverseZone" -ForegroundColor Green

}

# Toestaan zonetranfers naar server2
Write-Host "[INFO] Toelaten zonetransfers naar $secundaireDNS" -ForegroundColor Yellow
Set-DnsServerPrimaryZone -Name $forwardZone -SecureSecondaries TransferToSecureServers -SecondaryServers $secundaireIP -Notify Notify
Set-DnsServerPrimaryZone -Name $reverseZone -SecureSecondaries TransferToSecureServers -SecondaryServers $secundaireIP -Notify Notify

#-------------------------------------------
# Configuratie IIS webserver
#-------------------------------------------

Write-Host "`n=== CONFIGUREREN IIS WEBSERVER ===`n" -ForegroundColor Cyan

# Installeren IIS webserver rol
if(-not (get-WindowsFeature Web-Server).Installed) {
    Write-Host "[...] Installeren van de IIS webserver rol" -ForegroundColor Yellow
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
    Write-Host "[OK] De IIS webserver rol werd succesvol geïnstalleerd" -ForegroundColor Green

} else {
    Write-Host "[OK] De IIS webserver rol werd reeds geïnstalleerd" -ForegroundColor Green

}

# Aanmaken index.html
if(-not(Test-Path -Path $html)) {
    Write-Host "[...] Aanmaken van de index.html pagina" -ForegroundColor Yellow
    Set-Content -Path $html -Value $inhoud -NoNewline
    Write-Host "[OK] De index.html pagina werd succesvol aangemaakt" -ForegroundColor Green

} else {
    Write-Host "[OK] De index.html pagina bestaat reeds" -ForegroundColor Green

} 

# Opstarten default website
if ((Get-WebsiteState -Name "Default Web Site").Value -ne "Started") {
    Write-Host "[...] Starten van de Default Web Site" -ForegroundColor Yellow
    Start-Website -Name "Default Web Site"
    Write-Host "[OK] Default Web Site werd succesvol gestart" -ForegroundColor Green

} else {
    Write-Host "[OK] Default Web Site draait reeds" -ForegroundColor Green

}

# Toevoegen A-record voor website
$existingRecord = Get-DnsServerResourceRecord -Name $hostRecord -ZoneName $forwardZone -RRType "A" -ErrorAction SilentlyContinue

if (-not $existingRecord) {
    Write-Host "[...] Toevoegen A-record '$hostRecord' voor '$ipWebserver'" -ForegroundColor Yellow
    Add-DnsServerResourceRecordA -Name $hostRecord -ZoneName $forwardZone -IPv4Address $ipWebserver
    Write-Host "[OK] A-record '$hostRecord' voor '$ipWebserver' werd succesvol toegevoegd" -ForegroundColor Green

} else {
    Write-Host "[OK] A-record '$hostRecord' voor '$ipWebserver' bestaat reeds" -ForegroundColor Green

}

#-------------------------------------------
# Autorisatie DHCP server
#-------------------------------------------

Write-Host "`n=== AUTORISEREN DHCP server ===`n" -ForegroundColor Cyan

# Installeren RSAT DHCP-beheermodule
if (-not (Get-WindowsFeature -Name RSAT-DHCP).Installed) {
    Write-Host "[...] Installeren RSAT-DHCP" -ForegroundColor Yellow
    Install-WindowsFeature -Name RSAT-DHCP -IncludeManagementTools
     Write-Host "[OK] RSAT-DHCP werd succesvol geïnstalleerd" -ForegroundColor Green

} else {
    Write-Host "[OK] RSAT-DHCP werd reeds geïnstalleerd" -ForegroundColor Green

}

# Server3 autoriseren als DHCP server binnen het domein
$isAuthorized = Invoke-Command -ComputerName "server1.WS26-JDV.hogent" -Credential $credentials -ScriptBlock {
    Get-DhcpServerInDC | Where-Object { $_.IPAddress -eq "192.168.26.30" -or $_.DnsName -eq "server3.WS26-JDV.hogent" }
}

if (-not $isAuthorized) {
    Write-Host "[...] Autoriseren server3 als DHCP-server in Active Directory" -ForegroundColor Yellow
    Invoke-Command -ComputerName "server1.WS26-JDV.hogent" -Credential $credentials -ScriptBlock {
        Add-DhcpServerInDC -DnsName "server3.WS26-JDV.hogent" -IPAddress "192.168.26.30"
    }
    Write-Host "[OK] Server3 werd succesvol geautoriseerd als DHCP-server in Active Directory." -ForegroundColor Green

} else {
    Write-Host "[OK] Server3 is reeds geautoriseerd als DHCP-server in Active Directory." -ForegroundColor Green

}