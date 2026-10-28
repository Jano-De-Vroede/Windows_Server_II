#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Controleert alle criteria van deel 1 voor server1 (domeincontroller, primaire DNS, IIS).

.DESCRIPTION
    Uitvoeren op server1, als Domain Admin. De ID's (S1.xx) komen overeen met criteria-deel1.md.
    Resultaat per criterium: PASS, WARN (aandachtspunt) of FAIL.
    De exitcode van het script is het aantal FAIL's (0 = alles OK).

.PARAMETER Dcdiag
    Voert ook 'dcdiag /q' uit (duurt enkele minuten).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\vagrant\scripts\Check-Server1.ps1
#>
[CmdletBinding()]
param(
    [string]$Domain = (Get-CimInstance Win32_ComputerSystem).Domain,
    [string]$Server1Name = 'server1',
    [string]$Server2Name = 'server2',
    [string]$Server3Name = 'server3',
    [string]$ClientName = 'client',
    [string]$Server1IP = '192.168.26.10',
    [string]$Server2IP = '192.168.26.20',
    [string]$Server3IP = '192.168.26.30',
    [string]$Prefix = '192.168.26.',
    [string[]]$GenegeerdeGebruikers = @('Administrator', 'Guest', 'krbtgt', 'vagrant'),
    [switch]$Dcdiag
)

# ----------------------------------------------------------------------------
# Hulpfuncties (identiek in alle Check-*.ps1 scripts)
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

function Get-ReverseName {
    param([string]$IP)
    $o = $IP.Split('.')
    return ('{0}.{1}.{2}.{3}.in-addr.arpa' -f $o[3], $o[2], $o[1], $o[0])
}

function Initialize-FirewallCache {
    $script:FwRules = @(Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction SilentlyContinue)
    $script:FwPorts = @{}
    Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue | ForEach-Object { $script:FwPorts[$_.InstanceID] = $_ }
}

function Test-InboundAllow {
    param(
        [int]$Port,
        [ValidateSet('TCP', 'UDP')][string]$Protocol = 'TCP',
        [string[]]$Groups = @()
    )
    foreach ($r in $script:FwRules) {
        if ($Groups.Count -gt 0 -and ($Groups -contains $r.DisplayGroup)) { return $true }
        $pf = $script:FwPorts[$r.InstanceID]
        if (-not $pf) { $pf = $r | Get-NetFirewallPortFilter }
        if ("$($pf.Protocol)" -ne $Protocol) { continue }
        foreach ($p in @($pf.LocalPort)) {
            if ("$p" -eq "$Port") { return $true }
            if ("$p" -match '^(\d+)-(\d+)$') {
                if ($Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $true }
            }
        }
    }
    return $false
}

function Get-AllowAllRules {
    $apps = @{}
    $svcs = @{}
    Get-NetFirewallApplicationFilter -All -ErrorAction SilentlyContinue | ForEach-Object { $apps[$_.InstanceID] = $_ }
    Get-NetFirewallServiceFilter -All -ErrorAction SilentlyContinue | ForEach-Object { $svcs[$_.InstanceID] = $_ }
    foreach ($r in $script:FwRules) {
        $pf = $script:FwPorts[$r.InstanceID]
        if (-not $pf) { continue }
        $prog = "$($apps[$r.InstanceID].Program)"
        $svc = "$($svcs[$r.InstanceID].Service)"
        if ("$($pf.Protocol)" -eq 'Any' -and (@($pf.LocalPort) -contains 'Any') -and $prog -eq 'Any' -and ($svc -eq 'Any' -or $svc -eq '')) {
            $r.DisplayName
        }
    }
}

# ----------------------------------------------------------------------------
# Voorbereiding
# ----------------------------------------------------------------------------
Import-Module ActiveDirectory, DnsServer, WebAdministration -ErrorAction SilentlyContinue

$DomainLower = $Domain.ToLower()
$ReverseZone = '26.168.192.in-addr.arpa'
$ipv4 = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$hoIP = @($ipv4 | Where-Object { $_.IPAddress -like "$Prefix*" })
$natIP = @($ipv4 | Where-Object { $_.IPAddress -notlike "$Prefix*" })
Initialize-FirewallCache

$servers = @(
    [pscustomobject]@{ L = 'a'; N = $Server1Name; IP = $Server1IP },
    [pscustomobject]@{ L = 'b'; N = $Server2Name; IP = $Server2IP },
    [pscustomobject]@{ L = 'c'; N = $Server3Name; IP = $Server3IP }
)

Write-Host ("Controle server1 - domein '{0}' - {1}" -f $Domain, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Systeem en netwerk
# ----------------------------------------------------------------------------
Test-Criterium 'S1.01' 'Systeem' 'Windows Server 2025 Core' {
    $os = Get-CimInstance Win32_OperatingSystem
    $type = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
    Res (($os.Caption -match '2025') -and ($type -eq 'Server Core')) "$($os.Caption) / $type"
}

Test-Criterium 'S1.02' 'Netwerk' "Host-only interface heeft statisch IP $Server1IP/24" {
    $ip = $hoIP | Where-Object { $_.IPAddress -eq $Server1IP } | Select-Object -First 1
    if (-not $ip) { return Res $false "IP $Server1IP niet gevonden (host-only IP's: $(($hoIP.IPAddress) -join ', '))" }
    $dhcp = (Get-NetIPInterface -InterfaceIndex $ip.InterfaceIndex -AddressFamily IPv4).Dhcp
    Res (($ip.PrefixLength -eq 24) -and ("$($ip.PrefixOrigin)" -eq 'Manual') -and ("$dhcp" -eq 'Disabled')) "prefix /$($ip.PrefixLength), origin $($ip.PrefixOrigin), DHCP $dhcp"
}

Test-Criterium 'S1.03' 'Netwerk' 'NAT-interface registreert zich niet in DNS' {
    if ($natIP.Count -eq 0) { return Res $false 'geen NAT-interface gevonden' }
    $fout = @($natIP | ForEach-Object { Get-DnsClient -InterfaceIndex $_.InterfaceIndex } |
            Where-Object { $_.RegisterThisConnectionsAddress })
    if ($fout.Count -eq 0) { return Res $true 'RegisterThisConnectionsAddress = False' }
    Res $false "registratie staat aan op: $(($fout.InterfaceAlias) -join ', ')"
}

Test-Criterium 'S1.04' 'Netwerk' 'DNS-client op host-only interface wijst naar zichzelf' {
    $ho = $hoIP | Select-Object -First 1
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $ho.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
    Res (($dns -contains $Server1IP) -or ($dns -contains '127.0.0.1')) "DNS-servers: $($dns -join ', ')"
}

# ----------------------------------------------------------------------------
# Active Directory
# ----------------------------------------------------------------------------
Test-Criterium 'S1.05' 'AD' 'Server is domeincontroller' {
    $rol = (Get-CimInstance Win32_ComputerSystem).DomainRole
    Res ($rol -ge 4) "DomainRole = $rol (4 of 5 = domeincontroller)"
}

Test-Criterium 'S1.06' 'AD' 'Domeinnaam heeft de vorm WS26-<initialen>.hogent' {
    Res ($Domain -match '^WS26-[A-Za-z]+\.hogent$') $Domain
}

Test-Criterium 'S1.07' 'AD' 'Forest functional level = Windows Server 2025' {
    $cfg = (Get-ADRootDSE).configurationNamingContext
    $lvl = (Get-ADObject -Identity "CN=Partitions,$cfg" -Properties 'msDS-Behavior-Version').'msDS-Behavior-Version'
    Res ($lvl -eq 10) "msDS-Behavior-Version = $lvl (10 = Windows Server 2025)"
}

Test-Criterium 'S1.08' 'AD' 'Domain functional level = Windows Server 2025' {
    $dn = (Get-ADDomain).DistinguishedName
    $lvl = (Get-ADObject -Identity $dn -Properties 'msDS-Behavior-Version').'msDS-Behavior-Version'
    Res ($lvl -eq 10) "msDS-Behavior-Version = $lvl (10 = Windows Server 2025)"
}

Test-Criterium 'S1.09' 'AD' 'Minstens 3 OU''s (zonder Domain Controllers)' {
    $ous = @(Get-ADOrganizationalUnit -Filter * | Where-Object { $_.Name -ne 'Domain Controllers' })
    Res ($ous.Count -ge 3) "$($ous.Count) OU's: $(($ous.Name) -join ', ')"
}

Test-Criterium 'S1.10' 'AD' 'Minstens 4 actieve, zelfgemaakte gebruikers' {
    $u = @(Get-ADUser -Filter * | Where-Object { $_.Enabled -and ($GenegeerdeGebruikers -notcontains $_.SamAccountName) })
    Res ($u.Count -ge 4) "$($u.Count) gebruikers: $(($u.SamAccountName) -join ', ')"
}

Test-Criterium 'S1.11' 'AD' 'Minstens 2 gebruikers zijn Domain Admin' {
    $da = @(Get-ADGroupMember -Identity 'Domain Admins' -Recursive | Where-Object { $_.objectClass -eq 'user' } |
            Where-Object { $GenegeerdeGebruikers -notcontains $_.SamAccountName })
    Res ($da.Count -ge 2) "$($da.Count) Domain Admins: $(($da.SamAccountName) -join ', ')"
}

Test-Criterium 'S1.12' 'AD' 'Minstens 2 gebruikers zijn enkel Domain User (geen admin)' {
    $adminNamen = @()
    foreach ($g in 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators') {
        $adminNamen += @(Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue | ForEach-Object { $_.SamAccountName })
    }
    $u = @(Get-ADUser -Filter * | Where-Object { $_.Enabled -and ($GenegeerdeGebruikers -notcontains $_.SamAccountName) -and ($adminNamen -notcontains $_.SamAccountName) })
    Res ($u.Count -ge 2) "$($u.Count) gewone gebruikers: $(($u.SamAccountName) -join ', ')"
}

Test-Criterium 'S1.13' 'AD' 'AD-services draaien (NTDS, Netlogon, KDC, DNS)' {
    $stop = @('NTDS', 'Netlogon', 'Kdc', 'DNS' | Where-Object { (Get-Service $_ -ErrorAction SilentlyContinue).Status -ne 'Running' })
    Res ($stop.Count -eq 0) "niet actief: $($stop -join ', ')"
}

if ($Dcdiag) {
    Test-Criterium 'S1.14' 'AD' 'dcdiag /q meldt geen fouten' {
        $uit = @(& dcdiag /q 2>&1)
        Res ($uit.Count -eq 0) "$($uit.Count) regels foutmelding"
    }
}

# ----------------------------------------------------------------------------
# DNS
# ----------------------------------------------------------------------------
Test-Criterium 'S1.17' 'DNS' 'DNS-rol geïnstalleerd en service draait' {
    $f = (Get-WindowsFeature DNS).Installed
    $s = (Get-Service DNS).Status
    Res ($f -and ("$s" -eq 'Running')) "feature geïnstalleerd: $f, service: $s"
}

Test-Criterium 'S1.18' 'DNS' "Forward zone $Domain is primair" {
    $z = Get-DnsServerZone -Name $Domain
    Res ("$($z.ZoneType)" -eq 'Primary') "type $($z.ZoneType), AD-geïntegreerd: $($z.IsDsIntegrated)"
}

Test-Criterium 'S1.19' 'DNS' "Reverse zone $ReverseZone is primair" {
    $z = Get-DnsServerZone -Name $ReverseZone
    Res (("$($z.ZoneType)" -eq 'Primary') -and $z.IsReverseLookupZone) "type $($z.ZoneType)"
}

foreach ($s in $servers) {
    Test-Criterium "S1.20$($s.L)" 'DNS' "Exact één A-record voor $($s.N) = $($s.IP)" {
        $a = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name $s.N -RRType A -ErrorAction SilentlyContinue)
        $ips = @($a | ForEach-Object { $_.RecordData.IPv4Address.IPAddressToString })
        Res (($a.Count -eq 1) -and ($ips[0] -eq $s.IP)) "gevonden: $($ips -join ', ')"
    }
}

foreach ($s in $servers) {
    Test-Criterium "S1.21$($s.L)" 'DNS' "Exact één PTR-record voor $($s.N)" {
        $octet = $s.IP.Split('.')[3]
        $p = @(Get-DnsServerResourceRecord -ZoneName $ReverseZone -Name $octet -RRType PTR -ErrorAction SilentlyContinue)
        $doel = @($p | ForEach-Object { $_.RecordData.PtrDomainName })
        Res (($p.Count -eq 1) -and ($doel[0] -like "$($s.N).$Domain*")) "gevonden: $($doel -join ', ')"
    }
}

Test-Criterium 'S1.22' 'DNS' 'Geen A-records met een ander IP dan 192.168.26.x (geen NAT-adressen)' {
    $zones = @($Domain)
    if (Get-DnsServerZone -Name "_msdcs.$Domain" -ErrorAction SilentlyContinue) { $zones += "_msdcs.$Domain" }
    $slecht = @()
    foreach ($z in $zones) {
        $slecht += @(Get-DnsServerResourceRecord -ZoneName $z -RRType A -ErrorAction SilentlyContinue |
                Where-Object { $_.RecordData.IPv4Address.IPAddressToString -notlike "$Prefix*" } |
                ForEach-Object { "$($_.HostName)=$($_.RecordData.IPv4Address.IPAddressToString)" })
    }
    Res ($slecht.Count -eq 0) "vreemde records: $($slecht -join ', ')"
}

Test-Criterium 'S1.23' 'DNS' 'De client heeft geen A-record in DNS' {
    $a = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name $ClientName -RRType A -ErrorAction SilentlyContinue)
    Res ($a.Count -eq 0) "$($a.Count) record(s) voor '$ClientName'"
}

Test-Criterium 'S1.24' 'DNS' 'NS-records van forward en reverse zone tonen beide DNS-servers' {
    $verwacht = @("$Server1Name.$DomainLower", "$Server2Name.$DomainLower")
    $fwd = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name '@' -RRType NS | ForEach-Object { $_.RecordData.NameServer.ToLower().TrimEnd('.') })
    $rev = @(Get-DnsServerResourceRecord -ZoneName $ReverseZone -Name '@' -RRType NS | ForEach-Object { $_.RecordData.NameServer.ToLower().TrimEnd('.') })
    $ontbreekt = @($verwacht | Where-Object { ($fwd -notcontains $_) -or ($rev -notcontains $_) })
    Res ($ontbreekt.Count -eq 0) "forward: $($fwd -join ', ') | reverse: $($rev -join ', ')"
}

Test-Criterium 'S1.25' 'DNS' "Zone transfer naar $Server2IP is toegestaan (forward en reverse)" {
    $detail = @()
    $allesOk = $true
    foreach ($naam in $Domain, $ReverseZone) {
        $z = Get-DnsServerZone -Name $naam
        $mode = "$($z.SecureSecondaries)"
        $secs = @($z.SecondaryServers | ForEach-Object { $_.ToString() })
        $ok = ($mode -eq 'TransferAnyServer') -or ($mode -eq 'TransferToZoneNameServer') -or (($mode -eq 'TransferToSecureServers') -and ($secs -contains $Server2IP))
        if (-not $ok) { $allesOk = $false }
        $detail += "$naam=$mode"
    }
    Res $allesOk ($detail -join ' | ')
}

Test-Criterium 'S1.26' 'DNS' "Record 'intranet' bestaat en wijst naar server1" {
    $r = Resolve-DnsName "intranet.$Domain" -Type A -Server $Server1IP -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'A' }
    $ips = @($r | ForEach-Object { $_.IPAddress })
    Res ($ips -contains $Server1IP) "intranet.$Domain -> $($ips -join ', ')"
}

# ----------------------------------------------------------------------------
# IIS
# ----------------------------------------------------------------------------
Test-Criterium 'S1.29' 'IIS' 'IIS-rol geïnstalleerd en W3SVC draait' {
    $f = (Get-WindowsFeature Web-Server).Installed
    $s = (Get-Service W3SVC).Status
    Res ($f -and ("$s" -eq 'Running')) "feature geïnstalleerd: $f, W3SVC: $s"
}

Test-Criterium 'S1.30' 'IIS' 'Gestarte website met HTTP-binding op poort 80' {
    $sites = @(Get-Website | Where-Object { "$($_.State)" -eq 'Started' })
    $p80 = @($sites | Where-Object { @($_.Bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation -like '*:80:*' }).Count -gt 0 })
    Res ($p80.Count -gt 0) "sites op poort 80: $(($p80.Name) -join ', ')"
}

Test-Criterium 'S1.31' 'IIS' "http://intranet.$Domain geeft HTTP 200 met 'Hello World'" {
    $r = Invoke-WebRequest -Uri "http://intranet.$Domain" -UseBasicParsing -TimeoutSec 15
    Res (($r.StatusCode -eq 200) -and ($r.Content -match 'hello\s+world')) "HTTP $($r.StatusCode)"
}

# ----------------------------------------------------------------------------
# Firewall
# ----------------------------------------------------------------------------
Test-Criterium 'S1.32' 'Firewall' 'Firewall actief op alle profielen' {
    $uit = @(Get-NetFirewallProfile | Where-Object { "$($_.Enabled)" -ne 'True' })
    Res ($uit.Count -eq 0) "uitgeschakeld: $(($uit.Name) -join ', ')"
}

Test-Criterium 'S1.33' 'Firewall' 'Default policy inkomend = Block op alle profielen' {
    $fout = @(Get-NetFirewallProfile | Where-Object { "$($_.DefaultInboundAction)" -ne 'Block' })
    Res ($fout.Count -eq 0) "niet op Block: $(($fout | ForEach-Object { "$($_.Name)=$($_.DefaultInboundAction)" }) -join ', ')"
}

Test-Criterium 'S1.34' 'Firewall' 'Inkomend toegelaten: DNS (TCP en UDP 53)' {
    $tcp = Test-InboundAllow -Port 53 -Protocol TCP -Groups 'DNS Service'
    $udp = Test-InboundAllow -Port 53 -Protocol UDP -Groups 'DNS Service'
    Res ($tcp -and $udp) "TCP: $tcp, UDP: $udp"
}

Test-Criterium 'S1.35' 'Firewall' 'Inkomend toegelaten: HTTP (TCP 80)' {
    $ok = Test-InboundAllow -Port 80 -Protocol TCP -Groups 'World Wide Web Services (HTTP Traffic-In)'
    Res $ok "TCP 80: $ok"
}

Test-Criterium 'S1.36' 'Firewall' 'Inkomend toegelaten: AD-poorten (88, 135, 389, 445, 464, 3268)' {
    $tests = @(
        @(88, 'TCP'), @(88, 'UDP'), @(135, 'TCP'), @(389, 'TCP'), @(389, 'UDP'),
        @(445, 'TCP'), @(464, 'TCP'), @(3268, 'TCP')
    )
    $mist = @()
    foreach ($t in $tests) {
        if (-not (Test-InboundAllow -Port $t[0] -Protocol $t[1] -Groups 'Active Directory Domain Services')) { $mist += "$($t[1]) $($t[0])" }
    }
    Res ($mist.Count -eq 0) "ontbreekt: $($mist -join ', ')"
}

Test-Criterium 'S1.37' 'Firewall' 'Geen allow-all inbound regel' -Waarschuwing {
    $regels = @(Get-AllowAllRules)
    Res ($regels.Count -eq 0) "regels: $($regels -join '; ')"
}

Write-Samenvatting
