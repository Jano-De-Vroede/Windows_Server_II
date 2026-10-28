#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Controleert alle criteria van deel 1 voor server2 (secundaire DNS, geen domeincontroller).

.DESCRIPTION
    Uitvoeren op server2, als Domain Admin. De ID's (S2.xx) komen overeen met criteria-deel1.md.
    Resultaat per criterium: PASS, WARN (aandachtspunt) of FAIL.
    De exitcode van het script is het aantal FAIL's (0 = alles OK).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\vagrant\scripts\Check-Server2.ps1
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
    [string]$Prefix = '192.168.26.'
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
Import-Module DnsServer -ErrorAction SilentlyContinue

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

Write-Host ("Controle server2 - domein '{0}' - {1}" -f $Domain, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Systeem en netwerk
# ----------------------------------------------------------------------------
Test-Criterium 'S2.01' 'Systeem' 'Windows Server 2025 Core' {
    $os = Get-CimInstance Win32_OperatingSystem
    $type = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
    Res (($os.Caption -match '2025') -and ($type -eq 'Server Core')) "$($os.Caption) / $type"
}

Test-Criterium 'S2.02' 'Netwerk' "Host-only interface heeft statisch IP $Server2IP/24" {
    $ip = $hoIP | Where-Object { $_.IPAddress -eq $Server2IP } | Select-Object -First 1
    if (-not $ip) { return Res $false "IP $Server2IP niet gevonden (host-only IP's: $(($hoIP.IPAddress) -join ', '))" }
    $dhcp = (Get-NetIPInterface -InterfaceIndex $ip.InterfaceIndex -AddressFamily IPv4).Dhcp
    Res (($ip.PrefixLength -eq 24) -and ("$($ip.PrefixOrigin)" -eq 'Manual') -and ("$dhcp" -eq 'Disabled')) "prefix /$($ip.PrefixLength), origin $($ip.PrefixOrigin), DHCP $dhcp"
}

Test-Criterium 'S2.03' 'Netwerk' 'NAT-interface registreert zich niet in DNS' {
    if ($natIP.Count -eq 0) { return Res $false 'geen NAT-interface gevonden' }
    $fout = @($natIP | ForEach-Object { Get-DnsClient -InterfaceIndex $_.InterfaceIndex } |
            Where-Object { $_.RegisterThisConnectionsAddress })
    if ($fout.Count -eq 0) { return Res $true 'RegisterThisConnectionsAddress = False' }
    Res $false "registratie staat aan op: $(($fout.InterfaceAlias) -join ', ')"
}

Test-Criterium 'S2.04' 'Netwerk' "DNS-client wijst naar de primaire DNS ($Server1IP)" {
    $ho = $hoIP | Select-Object -First 1
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $ho.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
    Res ($dns -contains $Server1IP) "DNS-servers: $($dns -join ', ')"
}

Test-Criterium 'S2.05' 'Domein' "Server is lid van het domein $Domain" {
    $cs = Get-CimInstance Win32_ComputerSystem
    Res ($cs.PartOfDomain -and ($cs.Domain -eq $Domain) -and ($Domain -match '^WS26-[A-Za-z]+\.hogent$')) "PartOfDomain: $($cs.PartOfDomain), domein: $($cs.Domain)"
}

Test-Criterium 'S2.06' 'Domein' 'Server is geen domeincontroller' {
    $rol = (Get-CimInstance Win32_ComputerSystem).DomainRole
    $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
    $adds = (Get-WindowsFeature AD-Domain-Services).Installed
    Res (($rol -eq 3) -and (-not $ntds) -and (-not $adds)) "DomainRole = $rol (3 = member server), NTDS-service: $([bool]$ntds), AD DS-feature: $adds"
}

# ----------------------------------------------------------------------------
# DNS (secundaire server)
# ----------------------------------------------------------------------------
Test-Criterium 'S2.07' 'DNS' 'DNS-rol geïnstalleerd en service draait' {
    $f = (Get-WindowsFeature DNS).Installed
    $s = (Get-Service DNS).Status
    Res ($f -and ("$s" -eq 'Running')) "feature geïnstalleerd: $f, service: $s"
}

Test-Criterium 'S2.08' 'DNS' "Forward zone $Domain is secundair met master $Server1IP" {
    $z = Get-DnsServerZone -Name $Domain
    $m = @($z.MasterServers | ForEach-Object { $_.ToString() })
    Res (("$($z.ZoneType)" -eq 'Secondary') -and ($m -contains $Server1IP)) "type $($z.ZoneType), masters: $($m -join ', ')"
}

Test-Criterium 'S2.09' 'DNS' "Reverse zone $ReverseZone is secundair met master $Server1IP" {
    $z = Get-DnsServerZone -Name $ReverseZone
    $m = @($z.MasterServers | ForEach-Object { $_.ToString() })
    Res (("$($z.ZoneType)" -eq 'Secondary') -and ($m -contains $Server1IP)) "type $($z.ZoneType), masters: $($m -join ', ')"
}

Test-Criterium 'S2.10' 'DNS' 'Zones zijn geladen en SOA-serienummer is gelijk aan dat van server1' {
    $detail = @()
    $ok = $true
    foreach ($naam in $Domain, $ReverseZone) {
        $s1 = (Resolve-DnsName $naam -Type SOA -Server $Server1IP -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'SOA' }).SerialNumber
        $s2 = (Resolve-DnsName $naam -Type SOA -Server $Server2IP -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'SOA' }).SerialNumber
        $records = @(Get-DnsServerResourceRecord -ZoneName $naam -ErrorAction Stop).Count
        if (($s1 -ne $s2) -or ($records -eq 0)) { $ok = $false }
        $detail += "$naam serial server1=$s1 server2=$s2 ($records records)"
    }
    Res $ok ($detail -join ' | ')
}

foreach ($s in $servers) {
    Test-Criterium "S2.11$($s.L)" 'DNS' "Exact één A-record voor $($s.N) = $($s.IP) (kopie op server2)" {
        $a = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name $s.N -RRType A -ErrorAction SilentlyContinue)
        $ips = @($a | ForEach-Object { $_.RecordData.IPv4Address.IPAddressToString })
        Res (($a.Count -eq 1) -and ($ips[0] -eq $s.IP)) "gevonden: $($ips -join ', ')"
    }
}

foreach ($s in $servers) {
    Test-Criterium "S2.12$($s.L)" 'DNS' "Exact één PTR-record voor $($s.N) (kopie op server2)" {
        $octet = $s.IP.Split('.')[3]
        $p = @(Get-DnsServerResourceRecord -ZoneName $ReverseZone -Name $octet -RRType PTR -ErrorAction SilentlyContinue)
        $doel = @($p | ForEach-Object { $_.RecordData.PtrDomainName })
        Res (($p.Count -eq 1) -and ($doel[0] -like "$($s.N).$Domain*")) "gevonden: $($doel -join ', ')"
    }
}

Test-Criterium 'S2.13' 'DNS' 'NS-records tonen beide DNS-servers' {
    $verwacht = @("$Server1Name.$DomainLower", "$Server2Name.$DomainLower")
    $fwd = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name '@' -RRType NS | ForEach-Object { $_.RecordData.NameServer.ToLower().TrimEnd('.') })
    $rev = @(Get-DnsServerResourceRecord -ZoneName $ReverseZone -Name '@' -RRType NS | ForEach-Object { $_.RecordData.NameServer.ToLower().TrimEnd('.') })
    $ontbreekt = @($verwacht | Where-Object { ($fwd -notcontains $_) -or ($rev -notcontains $_) })
    Res ($ontbreekt.Count -eq 0) "forward: $($fwd -join ', ') | reverse: $($rev -join ', ')"
}

Test-Criterium 'S2.14' 'DNS' 'Geen records met NAT-adressen en geen record van de client' {
    $slecht = @(Get-DnsServerResourceRecord -ZoneName $Domain -RRType A -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordData.IPv4Address.IPAddressToString -notlike "$Prefix*" } |
            ForEach-Object { "$($_.HostName)=$($_.RecordData.IPv4Address.IPAddressToString)" })
    $client = @(Get-DnsServerResourceRecord -ZoneName $Domain -Name $ClientName -RRType A -ErrorAction SilentlyContinue)
    Res (($slecht.Count -eq 0) -and ($client.Count -eq 0)) "vreemde records: $($slecht -join ', '); client-records: $($client.Count)"
}

Test-Criterium 'S2.15' 'DNS' "Queries rechtstreeks aan server2 ($Server2IP) worden correct beantwoord" {
    $fouten = @()
    foreach ($s in $servers) {
        $a = @(Resolve-DnsName "$($s.N).$Domain" -Type A -Server $Server2IP -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' })
        if (($a.Count -ne 1) -or ($a[0].IPAddress -ne $s.IP)) { $fouten += "A $($s.N)" }
        $p = @(Resolve-DnsName (Get-ReverseName $s.IP) -Type PTR -Server $Server2IP -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'PTR' })
        if (($p.Count -ne 1) -or ($p[0].NameHost -notlike "$($s.N).$Domain*")) { $fouten += "PTR $($s.N)" }
    }
    $i = @(Resolve-DnsName "intranet.$Domain" -Server $Server2IP -DnsOnly -ErrorAction SilentlyContinue)
    if ($i.Count -eq 0) { $fouten += 'intranet' }
    Res ($fouten.Count -eq 0) "mislukt: $($fouten -join ', ')"
}

# ----------------------------------------------------------------------------
# Firewall
# ----------------------------------------------------------------------------
Test-Criterium 'S2.17' 'Firewall' 'Firewall actief op alle profielen' {
    $uit = @(Get-NetFirewallProfile | Where-Object { "$($_.Enabled)" -ne 'True' })
    Res ($uit.Count -eq 0) "uitgeschakeld: $(($uit.Name) -join ', ')"
}

Test-Criterium 'S2.18' 'Firewall' 'Default policy inkomend = Block op alle profielen' {
    $fout = @(Get-NetFirewallProfile | Where-Object { "$($_.DefaultInboundAction)" -ne 'Block' })
    Res ($fout.Count -eq 0) "niet op Block: $(($fout | ForEach-Object { "$($_.Name)=$($_.DefaultInboundAction)" }) -join ', ')"
}

Test-Criterium 'S2.19' 'Firewall' 'Inkomend toegelaten: DNS (TCP en UDP 53)' {
    $tcp = Test-InboundAllow -Port 53 -Protocol TCP -Groups 'DNS Service'
    $udp = Test-InboundAllow -Port 53 -Protocol UDP -Groups 'DNS Service'
    Res ($tcp -and $udp) "TCP: $tcp, UDP: $udp"
}

Test-Criterium 'S2.20' 'Firewall' 'Inkomend toegelaten: RPC (TCP 135) voor beheer met RSAT' {
    $ok = Test-InboundAllow -Port 135 -Protocol TCP -Groups 'Remote Service Management', 'COM+ Network Access'
    Res $ok "TCP 135: $ok"
}

Test-Criterium 'S2.21' 'Firewall' 'Geen allow-all inbound regel' -Waarschuwing {
    $regels = @(Get-AllowAllRules)
    Res ($regels.Count -eq 0) "regels: $($regels -join '; ')"
}

Write-Samenvatting
