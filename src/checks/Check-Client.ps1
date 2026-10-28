#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Controleert alle criteria van deel 1 voor de Windows 11 client (DHCP, RSAT, vertrouwen van de CA, intranet).

.DESCRIPTION
    Uitvoeren op de client in een PowerShell-venster als administrator, ingelogd als Domain Admin.
    De ID's (C.xx) komen overeen met criteria-deel1.md.
    Resultaat per criterium: PASS, WARN (aandachtspunt) of FAIL.
    De exitcode van het script is het aantal FAIL's (0 = alles OK).

.PARAMETER RenewLease
    Vernieuwt eerst het DHCP-lease van de client (ipconfig /renew) voor de controles starten.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Check-Client.ps1 -RenewLease
#>
[CmdletBinding()]
param(
    [string]$Domain = (Get-CimInstance Win32_ComputerSystem).Domain,
    [string]$Server1Name = 'server1',
    [string]$Server2Name = 'server2',
    [string]$Server3Name = 'server3',
    [string]$Server1IP = '192.168.26.10',
    [string]$Server2IP = '192.168.26.20',
    [string]$Server3IP = '192.168.26.30',
    [string]$Prefix = '192.168.26.',
    [int]$LeaseStart = 100,
    [int]$LeaseEnd = 150,
    [switch]$RenewLease
)

# ----------------------------------------------------------------------------
# Hulpfuncties (identiek in alle Check-*.ps1 scripts, behalve de firewallfuncties)
# ----------------------------------------------------------------------------
$script:Resultaten = New-Object System.Collections.ArrayList

function Res {
    param([bool]$Ok, [string]$Detail = '')
    [pscustomobject]@{ Ok = $Ok; Detail = $Detail }
}

function Test-Criterium {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Categorie,
        [Parameter(Mandatory)][string]$Naam,
        [Parameter(Mandatory)][scriptblock]$Test,
        [switch]$Waarschuwing
    )
    $ErrorActionPreference = 'Stop'
    $ok = $false
    $detail = ''
    try {
        $res = @(& $Test) | Select-Object -Last 1
        if ($res -is [bool]) { $ok = $res }
        elseif ($res -and $res.PSObject.Properties['Ok']) { $ok = [bool]$res.Ok; $detail = [string]$res.Detail }
    }
    catch {
        $ok = $false
        $detail = $_.Exception.Message
    }
    if ($ok) { $status = 'PASS'; $kleur = 'Green' }
    elseif ($Waarschuwing) { $status = 'WARN'; $kleur = 'Yellow' }
    else { $status = 'FAIL'; $kleur = 'Red' }
    $tekst = $Naam
    if ($detail) { $tekst = "$Naam  ->  $detail" }
    Write-Host ("[{0}] {1} {2}: {3}" -f $status, $Id, $Categorie, $tekst) -ForegroundColor $kleur
    [void]$script:Resultaten.Add([pscustomobject]@{ Status = $status; Id = $Id; Naam = $Naam; Detail = $detail })
}

function Write-Samenvatting {
    $pass = @($script:Resultaten | Where-Object { $_.Status -eq 'PASS' }).Count
    $warn = @($script:Resultaten | Where-Object { $_.Status -eq 'WARN' }).Count
    $fail = @($script:Resultaten | Where-Object { $_.Status -eq 'FAIL' }).Count
    Write-Host ''
    Write-Host ('=' * 70)
    Write-Host ("Resultaat {0}: {1} PASS, {2} WARN, {3} FAIL (totaal {4})" -f $env:COMPUTERNAME, $pass, $warn, $fail, $script:Resultaten.Count) -ForegroundColor Cyan
    if ($fail -gt 0) {
        Write-Host 'Te herstellen:' -ForegroundColor Red
        $script:Resultaten | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.Id, $_.Naam) -ForegroundColor Red }
    }
    if ($warn -gt 0) {
        Write-Host 'Aandachtspunten:' -ForegroundColor Yellow
        $script:Resultaten | Where-Object { $_.Status -eq 'WARN' } | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.Id, $_.Naam) -ForegroundColor Yellow }
    }
    exit ([Math]::Min($fail, 255))
}

function Test-TcpPoort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutMs = 3000)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $c.Connected) {
            $c.EndConnect($iar)
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { $c.Close() }
}

function Get-LaatsteOctet {
    param([string]$IP)
    return [int]($IP.Split('.')[3])
}

# ----------------------------------------------------------------------------
# Voorbereiding
# ----------------------------------------------------------------------------
if ($RenewLease) {
    Write-Host 'DHCP-lease vernieuwen...' -ForegroundColor Cyan
    & ipconfig /renew | Out-Null
    Start-Sleep -Seconds 3
}

$DomainLower = $Domain.ToLower()
$ComputerNaam = $env:COMPUTERNAME
$ipv4 = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$hoIP = @($ipv4 | Where-Object { $_.IPAddress -like "$Prefix*" })

# Gegevens van de CA uit Active Directory (Enrollment Services)
$caNaam = $null
$caHost = $null
$caCert = $null
try {
    $cfg = ([adsi]'LDAP://RootDSE').Properties['configurationNamingContext'].Value
    $es = [adsi]"LDAP://CN=Enrollment Services,CN=Public Key Services,CN=Services,$cfg"
    $ca = $es.psbase.Children | Select-Object -First 1
    $caNaam = [string]$ca.Properties['cn'].Value
    $caHost = [string]$ca.Properties['dNSHostName'].Value
    $bytes = [byte[]]$ca.Properties['cACertificate'].Value
    $caCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (, $bytes)
}
catch { }
if (-not $caHost) { $caHost = "$Server3Name.$DomainLower" }

Write-Host ("Controle client ({0}) - domein '{1}' - {2}" -f $ComputerNaam, $Domain, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Systeem en netwerk
# ----------------------------------------------------------------------------
Test-Criterium 'C.01' 'Systeem' 'Windows 11 Enterprise' {
    $os = Get-CimInstance Win32_OperatingSystem
    $ed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    Res (($os.Caption -match 'Windows 11') -and ($ed -match 'Enterprise')) "$($os.Caption) / $ed"
}

Test-Criterium 'C.02' 'Domein' "Client is lid van $Domain en het secure channel is OK" {
    $cs = Get-CimInstance Win32_ComputerSystem
    $sc = Test-ComputerSecureChannel
    Res ($cs.PartOfDomain -and ($cs.Domain -eq $Domain) -and $sc -and ($Domain -match '^WS26-[A-Za-z]+\.hogent$')) "domein: $($cs.Domain), secure channel: $sc"
}

Test-Criterium 'C.03' 'DHCP' "Host-only interface heeft een IP via DHCP binnen $Prefix$LeaseStart - $Prefix$LeaseEnd" {
    if ($hoIP.Count -eq 0) { return Res $false "geen IP in $Prefix* gevonden" }
    $ip = $hoIP | Select-Object -First 1
    $octet = Get-LaatsteOctet $ip.IPAddress
    $dhcp = "$($ip.PrefixOrigin)" -eq 'Dhcp'
    Res ($dhcp -and ($octet -ge $LeaseStart) -and ($octet -le $LeaseEnd)) "IP $($ip.IPAddress), origin $($ip.PrefixOrigin)"
}

Test-Criterium 'C.04' 'DHCP' "DHCP-server van de lease is $Server3IP (niet de VirtualBox DHCP-server)" {
    $ip = ($hoIP | Select-Object -First 1).IPAddress
    $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' | Where-Object { $_.IPAddress -contains $ip } | Select-Object -First 1
    Res (($cfg.DHCPEnabled) -and ($cfg.DHCPServer -eq $Server3IP)) "DHCP-server: $($cfg.DHCPServer), lease verkregen: $($cfg.DHCPLeaseObtained)"
}

Test-Criterium 'C.05' 'DHCP' "DNS-servers via DHCP = $Server1IP en $Server2IP" {
    $ho = $hoIP | Select-Object -First 1
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $ho.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
    Res (($dns -contains $Server1IP) -and ($dns -contains $Server2IP)) "DNS-servers: $($dns -join ', ')"
}

Test-Criterium 'C.06' 'DNS' 'Naamresolutie werkt (korte naam, FQDN en intranet)' {
    $fouten = @()
    try { $k = @([System.Net.Dns]::GetHostAddresses($Server1Name) | ForEach-Object { $_.IPAddressToString }); if ($k -notcontains $Server1IP) { $fouten += "korte naam $Server1Name -> $($k -join ',')" } }
    catch { $fouten += "korte naam $Server1Name" }
    foreach ($n in "$Server1Name.$Domain", "$Server2Name.$Domain", "$Server3Name.$Domain", "intranet.$Domain") {
        $r = @(Resolve-DnsName $n -Type A -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' })
        if ($r.Count -eq 0) { $fouten += $n }
    }
    Res ($fouten.Count -eq 0) "mislukt: $($fouten -join ', ')"
}

Test-Criterium 'C.07' 'DNS' 'Client registreert zich niet in DNS' {
    $actief = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq 'Connected' -and $_.InterfaceAlias -notlike 'Loopback*' } | ForEach-Object { $_.InterfaceIndex })
    $aan = @($actief | ForEach-Object { Get-DnsClient -InterfaceIndex $_ -ErrorAction SilentlyContinue } | Where-Object { $_.RegisterThisConnectionsAddress })
    $a = @(Resolve-DnsName "$ComputerNaam.$Domain" -Type A -Server $Server1IP -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' })
    Res (($aan.Count -eq 0) -and ($a.Count -eq 0)) "registratie aan op: $(($aan.InterfaceAlias) -join ', '); A-records voor $ComputerNaam`: $($a.Count)"
}

# ----------------------------------------------------------------------------
# RSAT en beheer
# ----------------------------------------------------------------------------
$nodig = @(
    'Rsat.ActiveDirectory.DS-LDS.Tools',
    'Rsat.Dns.Tools',
    'Rsat.DHCP.Tools',
    'Rsat.CertificateServices.Tools',
    'Rsat.GroupPolicy.Management.Tools'
)
$rsat = @(Get-WindowsCapability -Online -Name 'Rsat*' -ErrorAction SilentlyContinue | Where-Object { "$($_.State)" -eq 'Installed' })

Test-Criterium 'C.09' 'RSAT' 'RSAT geïnstalleerd: AD, DNS, DHCP, Certificate Services en Group Policy' {
    $mist = @($nodig | Where-Object { $p = $_; @($rsat | Where-Object { $_.Name -like "$p*" }).Count -eq 0 })
    Res ($mist.Count -eq 0) "ontbreekt: $($mist -join ', ')"
}

Test-Criterium 'C.10' 'RSAT' 'Enkel de nodige RSAT-tools zijn geïnstalleerd' -Waarschuwing {
    $extra = @($rsat | Where-Object { $n = $_.Name; @($nodig | Where-Object { $n -like "$_*" }).Count -eq 0 })
    Res ($extra.Count -eq 0) "extra geïnstalleerd: $(($extra.Name) -join ', ')"
}

Test-Criterium 'C.11' 'RSAT' 'Consoles beschikbaar (dsa, dnsmgmt, dhcpmgmt, certsrv, gpmc)' {
    $mist = @('dsa.msc', 'dnsmgmt.msc', 'dhcpmgmt.msc', 'certsrv.msc', 'gpmc.msc' | Where-Object { -not (Test-Path (Join-Path $env:windir "System32\$_")) })
    Res ($mist.Count -eq 0) "ontbreekt: $($mist -join ', ')"
}

Test-Criterium 'C.12' 'RSAT' 'Beheer op afstand werkt: AD, DNS (server1 en server2), DHCP en CA' {
    $fouten = @()
    try { [void](Get-ADDomain -Server $Server1IP -ErrorAction Stop) } catch { $fouten += 'AD (server1)' }
    try { [void](Get-DnsServerZone -ComputerName $Server1IP -ErrorAction Stop) } catch { $fouten += 'DNS (server1)' }
    try { [void](Get-DnsServerZone -ComputerName $Server2IP -ErrorAction Stop) } catch { $fouten += 'DNS (server2)' }
    try { [void](Get-DhcpServerv4Scope -ComputerName $Server3IP -ErrorAction Stop) } catch { $fouten += 'DHCP (server3)' }
    if ($caNaam) {
        $uit = & certutil -config "$caHost\$caNaam" -ping 2>&1
        if ($LASTEXITCODE -ne 0) { $fouten += 'CA (server3)' }
    }
    else { $fouten += 'CA (naam niet gevonden in AD)' }
    Res ($fouten.Count -eq 0) "mislukt: $($fouten -join ', ')"
}

Test-Criterium 'C.13' 'Netwerk' 'Poorten bereikbaar: server1 (389), server2 (53), server3 (80)' {
    $fouten = @()
    if (-not (Test-TcpPoort -ComputerName $Server1IP -Port 389)) { $fouten += "$Server1IP`:389" }
    if (-not (Test-TcpPoort -ComputerName $Server2IP -Port 53)) { $fouten += "$Server2IP`:53" }
    if (-not (Test-TcpPoort -ComputerName $Server3IP -Port 80)) { $fouten += "$Server3IP`:80" }
    Res ($fouten.Count -eq 0) "niet bereikbaar: $($fouten -join ', ')"
}

# ----------------------------------------------------------------------------
# CA en IIS vanaf de client
# ----------------------------------------------------------------------------
Test-Criterium 'C.14' 'CA' 'Root-certificaat van de CA staat in Trusted Root Certification Authorities' {
    if (-not $caCert) { return Res $false 'CA-certificaat niet gevonden in AD (Enrollment Services)' }
    $inRoot = Test-Path "Cert:\LocalMachine\Root\$($caCert.Thumbprint)"
    Res $inRoot "$($caCert.Subject), thumbprint $($caCert.Thumbprint), in Root store: $inRoot"
}

Test-Criterium 'C.15' 'CA' 'Root-certificaat wordt via een GPO verspreid (policy-sleutel aanwezig)' -Waarschuwing {
    if (-not $caCert) { return Res $false 'CA-certificaat niet gevonden in AD' }
    $bestaat = Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$($caCert.Thumbprint)"
    $gpos = ''
    if (Get-Command Get-GPO -ErrorAction SilentlyContinue) {
        $namen = @(Get-GPO -All -Server $Server1IP -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName })
        $gpos = "; GPO's in het domein: $($namen -join ', ')"
    }
    $tip = ''
    if (-not $bestaat) { $tip = ' (voer eerst gpupdate /force uit)' }
    Res $bestaat "policy-sleutel aanwezig: $bestaat$tip$gpos"
}

Test-Criterium 'C.16' 'IIS' "http://intranet.$Domain toont 'Hello World'" {
    $r = Invoke-WebRequest -Uri "http://intranet.$Domain" -UseBasicParsing -TimeoutSec 15
    Res (($r.StatusCode -eq 200) -and ($r.Content -match 'hello\s+world')) "HTTP $($r.StatusCode)"
}

Test-Criterium 'C.17' 'CA' "Web Enrollment http://$caHost/CertSrv is bereikbaar" {
    $r = Invoke-WebRequest -Uri "http://$caHost/CertSrv/" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 20
    Res ($r.StatusCode -eq 200) "HTTP $($r.StatusCode)"
}

Write-Host ''
Write-Host 'Handmatig te tonen in de demo (zie criteria-deel1.md, [M]-items): C.08 en C.18.' -ForegroundColor DarkGray
Write-Samenvatting
