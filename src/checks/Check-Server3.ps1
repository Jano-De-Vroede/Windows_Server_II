#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Controleert alle criteria van deel 1 voor server3 (Certification Authority en DHCP).

.DESCRIPTION
    Uitvoeren op server3, als Domain Admin. De ID's (S3.xx) komen overeen met criteria-deel1.md.
    Resultaat per criterium: PASS, WARN (aandachtspunt) of FAIL.
    De exitcode van het script is het aantal FAIL's (0 = alles OK).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\vagrant\scripts\Check-Server3.ps1
#>
[CmdletBinding()]
param(
    [string]$Domain = (Get-CimInstance Win32_ComputerSystem).Domain,
    [string]$Server1IP = '192.168.26.10',
    [string]$Server2IP = '192.168.26.20',
    [string]$Server3IP = '192.168.26.30',
    [string]$Prefix = '192.168.26.',
    [string]$ScopeId = '192.168.26.0',
    [string]$ScopeStart = '192.168.26.100',
    [string]$ScopeEnd = '192.168.26.200',
    [int]$ExclusionStart = 151,
    [int]$ExclusionEnd = 200
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
Import-Module DhcpServer -ErrorAction SilentlyContinue

$DomainLower = $Domain.ToLower()
$Fqdn = "$($env:COMPUTERNAME).$DomainLower".ToLower()
$ipv4 = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$hoIP = @($ipv4 | Where-Object { $_.IPAddress -like "$Prefix*" })
$natIP = @($ipv4 | Where-Object { $_.IPAddress -notlike "$Prefix*" })
Initialize-FirewallCache

# CA-gegevens (indien de CA al bestaat)
$caName = $null
$caCert = $null
try {
    $caName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' -ErrorAction Stop).Active
}
catch { }
if ($caName) {
    $caCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { ($_.Subject -match ('CN=' + [regex]::Escape($caName))) -and ($_.Subject -eq $_.Issuer) } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
}

function Get-DhcpOptieWaarde {
    param([int]$OptionId)
    $v = Get-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId $OptionId -ErrorAction SilentlyContinue
    if (-not $v) { $v = Get-DhcpServerv4OptionValue -OptionId $OptionId -ErrorAction SilentlyContinue }
    if ($v) { return @($v.Value | ForEach-Object { "$_" }) }
    return @()
}

function Get-LaatsteOctet {
    param([string]$IP)
    return [int]($IP.Split('.')[3])
}

Write-Host ("Controle server3 - domein '{0}' - {1}" -f $Domain, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
Write-Host ('=' * 70)

# ----------------------------------------------------------------------------
# Systeem en netwerk
# ----------------------------------------------------------------------------
Test-Criterium 'S3.01' 'Systeem' 'Windows Server 2025 Core' {
    $os = Get-CimInstance Win32_OperatingSystem
    $type = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
    Res (($os.Caption -match '2025') -and ($type -eq 'Server Core')) "$($os.Caption) / $type"
}

Test-Criterium 'S3.02' 'Netwerk' "Host-only interface heeft statisch IP $Server3IP/24" {
    $ip = $hoIP | Where-Object { $_.IPAddress -eq $Server3IP } | Select-Object -First 1
    if (-not $ip) { return Res $false "IP $Server3IP niet gevonden (host-only IP's: $(($hoIP.IPAddress) -join ', '))" }
    $dhcp = (Get-NetIPInterface -InterfaceIndex $ip.InterfaceIndex -AddressFamily IPv4).Dhcp
    Res (($ip.PrefixLength -eq 24) -and ("$($ip.PrefixOrigin)" -eq 'Manual') -and ("$dhcp" -eq 'Disabled')) "prefix /$($ip.PrefixLength), origin $($ip.PrefixOrigin), DHCP $dhcp"
}

Test-Criterium 'S3.03' 'Netwerk' 'NAT-interface registreert zich niet in DNS' {
    if ($natIP.Count -eq 0) { return Res $false 'geen NAT-interface gevonden' }
    $fout = @($natIP | ForEach-Object { Get-DnsClient -InterfaceIndex $_.InterfaceIndex } |
            Where-Object { $_.RegisterThisConnectionsAddress })
    if ($fout.Count -eq 0) { return Res $true 'RegisterThisConnectionsAddress = False' }
    Res $false "registratie staat aan op: $(($fout.InterfaceAlias) -join ', ')"
}

Test-Criterium 'S3.04' 'Netwerk' 'DNS-client wijst naar 192.168.26.10 en/of 192.168.26.20' {
    $ho = $hoIP | Select-Object -First 1
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $ho.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
    Res (($dns -contains $Server1IP) -or ($dns -contains $Server2IP)) "DNS-servers: $($dns -join ', ')"
}

Test-Criterium 'S3.05' 'Domein' "Server is lid van $Domain en geen domeincontroller" {
    $cs = Get-CimInstance Win32_ComputerSystem
    Res ($cs.PartOfDomain -and ($cs.Domain -eq $Domain) -and ($cs.DomainRole -eq 3) -and ($Domain -match '^WS26-[A-Za-z]+\.hogent$')) "domein: $($cs.Domain), DomainRole = $($cs.DomainRole) (3 = member server)"
}

Test-Criterium 'S3.06' 'DNS' 'Exact één A-record en één PTR-record voor deze server (via server1 en server2)' {
    $fouten = @()
    foreach ($dnsServer in $Server1IP, $Server2IP) {
        $a = @(Resolve-DnsName $Fqdn -Type A -Server $dnsServer -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' })
        if (($a.Count -ne 1) -or ($a[0].IPAddress -ne $Server3IP)) { $fouten += "A via $dnsServer ($($a.Count) record(s))" }
        $p = @(Resolve-DnsName (Get-ReverseName $Server3IP) -Type PTR -Server $dnsServer -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'PTR' })
        if (($p.Count -ne 1) -or ($p[0].NameHost -notlike "$Fqdn*")) { $fouten += "PTR via $dnsServer ($($p.Count) record(s))" }
    }
    Res ($fouten.Count -eq 0) "problemen: $($fouten -join ', ')"
}

# ----------------------------------------------------------------------------
# Certification Authority
# ----------------------------------------------------------------------------
Test-Criterium 'S3.07' 'CA' 'Rol AD CS (Certification Authority) geïnstalleerd en CertSvc draait' {
    $f = (Get-WindowsFeature ADCS-Cert-Authority).Installed
    $s = (Get-Service CertSvc).Status
    Res ($f -and ("$s" -eq 'Running')) "feature geïnstalleerd: $f, CertSvc: $s, CA-naam: $caName"
}

Test-Criterium 'S3.08' 'CA' 'CA is een Root CA (Enterprise Root of Standalone Root)' {
    $type = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$caName" -ErrorAction Stop).CAType
    $namen = @{ 0 = 'Enterprise Root CA'; 1 = 'Enterprise Subordinate CA'; 3 = 'Standalone Root CA'; 4 = 'Standalone Subordinate CA' }
    Res (($type -eq 0) -or ($type -eq 3)) "CAType = $type ($($namen[[int]$type]))"
}

Test-Criterium 'S3.09' 'CA' 'CA-certificaat bestaat, is geldig en staat in de Trusted Root store' {
    if (-not $caCert) { return Res $false 'CA-certificaat niet gevonden in Cert:\LocalMachine\My' }
    $geldig = ($caCert.NotBefore -le (Get-Date)) -and ($caCert.NotAfter -gt (Get-Date))
    $inRoot = Test-Path "Cert:\LocalMachine\Root\$($caCert.Thumbprint)"
    Res ($geldig -and $inRoot) "$($caCert.Subject), geldig tot $($caCert.NotAfter.ToString('yyyy-MM-dd')), in Root store: $inRoot"
}

Test-Criterium 'S3.10' 'CA' 'certutil -ping naar de CA slaagt' {
    $uit = & certutil -config "$Fqdn\$caName" -ping 2>&1
    Res ($LASTEXITCODE -eq 0) "exitcode $LASTEXITCODE, config $Fqdn\$caName"
}

Test-Criterium 'S3.11' 'CA' 'Root-certificaat wordt via een GPO verspreid (policy-sleutel aanwezig)' -Waarschuwing {
    if (-not $caCert) { return Res $false 'CA-certificaat niet gevonden' }
    $sleutel = "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$($caCert.Thumbprint)"
    $bestaat = Test-Path $sleutel
    $tip = ''
    if (-not $bestaat) { $tip = ' (voer eerst gpupdate /force uit; zonder GPO is enkel de Enterprise CA-publicatie in AD actief)' }
    Res $bestaat "policy-sleutel aanwezig: $bestaat$tip"
}

Test-Criterium 'S3.12' 'CA' 'Role service Certification Authority Web Enrollment geïnstalleerd' {
    $f = (Get-WindowsFeature ADCS-Web-Enrollment).Installed
    $w = (Get-Service W3SVC -ErrorAction SilentlyContinue).Status
    Res ($f -and ("$w" -eq 'Running')) "feature geïnstalleerd: $f, W3SVC: $w"
}

Test-Criterium 'S3.13' 'CA' "http://$Fqdn/CertSrv is bereikbaar (HTTP 200)" {
    $r = Invoke-WebRequest -Uri "http://$Fqdn/CertSrv/" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 20
    Res ($r.StatusCode -eq 200) "HTTP $($r.StatusCode)"
}

# ----------------------------------------------------------------------------
# DHCP
# ----------------------------------------------------------------------------
Test-Criterium 'S3.16' 'DHCP' 'DHCP-rol geïnstalleerd en service DHCPServer draait' {
    $f = (Get-WindowsFeature DHCP).Installed
    $s = (Get-Service DHCPServer).Status
    Res ($f -and ("$s" -eq 'Running')) "feature geïnstalleerd: $f, service: $s"
}

Test-Criterium 'S3.17' 'DHCP' 'DHCP-server is geautoriseerd in Active Directory' {
    $a = @(Get-DhcpServerInDC | Where-Object { ($_.IPAddress.ToString() -eq $Server3IP) -or ($_.DnsName -like "$($env:COMPUTERNAME).*") })
    Res ($a.Count -gt 0) "geautoriseerde servers in AD: $(((Get-DhcpServerInDC).IPAddress | ForEach-Object { $_.ToString() }) -join ', ')"
}

Test-Criterium 'S3.18' 'DHCP' 'Lokale groepen DHCP Administrators en DHCP Users bestaan' -Waarschuwing {
    $g = @('DHCP Administrators', 'DHCP Users' | Where-Object { Get-LocalGroup -Name $_ -ErrorAction SilentlyContinue })
    Res ($g.Count -eq 2) "gevonden: $($g -join ', ')"
}

Test-Criterium 'S3.19' 'DHCP' "Scope $ScopeId/24 is actief en loopt van $ScopeStart tot $ScopeEnd" {
    $s = Get-DhcpServerv4Scope -ScopeId $ScopeId
    $ok = ("$($s.State)" -eq 'Active') -and ($s.StartRange.ToString() -eq $ScopeStart) -and ($s.EndRange.ToString() -eq $ScopeEnd) -and ($s.SubnetMask.ToString() -eq '255.255.255.0')
    Res $ok "state $($s.State), $($s.StartRange) - $($s.EndRange), mask $($s.SubnetMask)"
}

Test-Criterium 'S3.20' 'DHCP' "Exclusion range: .$ExclusionStart t/m .$ExclusionEnd uitgesloten en de rest van de range niet" {
    $bedekt = @{}
    $ranges = @(Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId -ErrorAction SilentlyContinue)
    foreach ($e in $ranges) {
        $van = Get-LaatsteOctet $e.StartRange.ToString()
        $tot = Get-LaatsteOctet $e.EndRange.ToString()
        for ($i = $van; $i -le $tot; $i++) { $bedekt[$i] = $true }
    }
    $beginScope = Get-LaatsteOctet $ScopeStart
    $eindScope = Get-LaatsteOctet $ScopeEnd
    $mist = @($ExclusionStart..$ExclusionEnd | Where-Object { -not $bedekt.ContainsKey($_) })
    $teVeel = @($beginScope..($ExclusionStart - 1) | Where-Object { $bedekt.ContainsKey($_) })
    $tekst = ($ranges | ForEach-Object { "$($_.StartRange)-$($_.EndRange)" }) -join ', '
    Res (($mist.Count -eq 0) -and ($teVeel.Count -eq 0)) "exclusions: $tekst; niet uitgesloten: $($mist.Count); onterecht uitgesloten: $($teVeel.Count)"
}

Test-Criterium 'S3.21' 'DHCP' "Optie 006 (DNS-servers) = $Server1IP en $Server2IP" {
    $w = Get-DhcpOptieWaarde 6
    $ok = ($w -contains $Server1IP) -and ($w -contains $Server2IP) -and (@($w | Where-Object { $_ -like '10.*' }).Count -eq 0)
    Res $ok "waarde: $($w -join ', ')"
}

Test-Criterium 'S3.22' 'DHCP' "Optie 015 (DNS-domeinnaam) = $Domain" {
    $w = Get-DhcpOptieWaarde 15
    Res ($w -contains $Domain) "waarde: $($w -join ', ')"
}

Test-Criterium 'S3.23' 'DHCP' 'Optie 003 (router) is niet ingesteld (geen gateway in dit netwerk)' -Waarschuwing {
    $w = Get-DhcpOptieWaarde 3
    Res ($w.Count -eq 0) "waarde: $($w -join ', ')"
}

Test-Criterium 'S3.24' 'DHCP' 'DHCP-server is enkel gebonden aan de host-only interface' -Waarschuwing {
    $b = @(Get-DhcpServerv4Binding)
    $ho = @($b | Where-Object { $_.IPAddress.ToString() -eq $Server3IP -and $_.BindingState })
    $andere = @($b | Where-Object { $_.IPAddress.ToString() -ne $Server3IP -and $_.BindingState })
    Res (($ho.Count -eq 1) -and ($andere.Count -eq 0)) "actieve bindings: $((($b | Where-Object { $_.BindingState }) | ForEach-Object { $_.IPAddress.ToString() }) -join ', ')"
}

Test-Criterium 'S3.25' 'DHCP' 'DNS-dynamic updates door de DHCP-server staan uit' -Waarschuwing {
    $d = Get-DhcpServerv4DnsSetting -ScopeId $ScopeId
    Res ("$($d.DynamicUpdates)" -eq 'Never') "DynamicUpdates = $($d.DynamicUpdates)"
}

Test-Criterium 'S3.26' 'DHCP' 'Minstens één lease, en alle leases liggen binnen .100-.150' {
    $l = @(Get-DhcpServerv4Lease -ScopeId $ScopeId -ErrorAction SilentlyContinue)
    $buiten = @($l | Where-Object { $o = Get-LaatsteOctet $_.IPAddress.ToString(); ($o -lt 100) -or ($o -gt 150) })
    Res (($l.Count -ge 1) -and ($buiten.Count -eq 0)) "$($l.Count) lease(s): $(($l | ForEach-Object { "$($_.IPAddress) ($($_.HostName))" }) -join ', ')"
}

# ----------------------------------------------------------------------------
# Firewall
# ----------------------------------------------------------------------------
Test-Criterium 'S3.29' 'Firewall' 'Firewall actief op alle profielen' {
    $uit = @(Get-NetFirewallProfile | Where-Object { "$($_.Enabled)" -ne 'True' })
    Res ($uit.Count -eq 0) "uitgeschakeld: $(($uit.Name) -join ', ')"
}

Test-Criterium 'S3.30' 'Firewall' 'Default policy inkomend = Block op alle profielen' {
    $fout = @(Get-NetFirewallProfile | Where-Object { "$($_.DefaultInboundAction)" -ne 'Block' })
    Res ($fout.Count -eq 0) "niet op Block: $(($fout | ForEach-Object { "$($_.Name)=$($_.DefaultInboundAction)" }) -join ', ')"
}

Test-Criterium 'S3.31' 'Firewall' 'Inkomend toegelaten: DHCP (UDP 67)' {
    $ok = Test-InboundAllow -Port 67 -Protocol UDP -Groups 'DHCP Server'
    Res $ok "UDP 67: $ok"
}

Test-Criterium 'S3.32' 'Firewall' 'Inkomend toegelaten: HTTP (TCP 80) voor Web Enrollment' {
    $ok = Test-InboundAllow -Port 80 -Protocol TCP -Groups 'World Wide Web Services (HTTP Traffic-In)'
    Res $ok "TCP 80: $ok"
}

Test-Criterium 'S3.33' 'Firewall' 'Inkomend toegelaten: RPC (TCP 135) voor beheer met RSAT' {
    $ok = Test-InboundAllow -Port 135 -Protocol TCP -Groups 'Remote Service Management', 'COM+ Network Access'
    Res $ok "TCP 135: $ok"
}

Test-Criterium 'S3.34' 'Firewall' 'Geen allow-all inbound regel' -Waarschuwing {
    $regels = @(Get-AllowAllRules)
    Res ($regels.Count -eq 0) "regels: $($regels -join '; ')"
}

Write-Samenvatting
