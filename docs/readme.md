# Deployment guide - Windows Server II (deel 1)

## 1. Uitrol van de omgeving

### 1.1 Requirements

- [ ] Benodigde software:
  - [ ] Vagrant
  - [ ] Oracle VirtualBox
- [ ] Vagrant boxes:
  - [ ] Windows Server 2025: `gusztavvargadr/windows-server-2025-standard-core (versie 2607.0.0)`
  - [ ] Windows 11 Enterprise: `gusztavvargadr/windows-11-25h2-enterprise (versie 2607.1.0)`
- [ ] Automatisatie scripts:
  - [ ] Vagrantfile
  - [ ] Configuration_Client_Initial.ps1
  - [ ] Configuration_Client_Services.ps1
  - [ ] Configuration_Server1_Initial.ps1
  - [ ] Configuration_Server1_Services.ps1
  - [ ] Configuration_Server2_Initial.ps1
  - [ ] Configuration_Server2_Services.ps1
  - [ ] Configuration_Server3_Initial.ps1
  - [ ] Configuration_Server3_Services.ps1

### 1.2 Overzicht gebruikers

| Gebruikersnaam | Wachtwoord  | Organizational Unit | Beschrijving                   |
| :------------- | ----------- | ------------------- | ------------------------------ |
| jdevroede      | JDVAdmin26! | Directie            | Domain Admin, Enterprise Admin |
| rjacobs        | JDVAdmin26! | IT                  | Domain Admin, Enterprise Admin |
| mbrondeel      | JDVUser26!  | Directie            | Domain User                    |
| bmarcelis      | JDVUser26!  | Bedienden           | Domain User                    |
| edevroede      | JDVUser26!  | Bedienden           | Domain User                    |
| odevroede      | JDVUser26!  | Bedienden           | Domain User                    |
| yvandegucht    | JDVUser26!  | IT                  | Domain User                    |

### 1.3 Stappenplan

Dit stappenplan vereist dat bovenstaande requirements allemaal aanwezig zijn om een de omgeving op een correcte manier te kunnen opzetten.

1. Maak een nieuwe folder aan en voeg volgende zaken toe:
   - Vagrantfile
   - Een folder met de naam _scripts_ waarin alle automatisatiescripts zitten (De naam van deze folder moet kloppen anders zal de vagrantfile de scripts niet vinden)
2. Open een terminal in dezelfde folder als waar de vagrantfile zich bevindt.
3. Controleer of je in de correcte map zit met het commando `vagrant status`. Als alles correct is krijg je onderstaan uitvoer te zien.

```powershell
PS C:\HOGENT\Schooljaar_2627\Windows Server II\WSII_Eindopdracht\src> vagrant status
Current machine states:

server1                   poweroff (virtualbox)
server2                   poweroff (virtualbox)
server3                   poweroff (virtualbox)
client                    poweroff (virtualbox)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run `vagrant status NAME`.

```

4. Bouw de omgeving met het commando `vagrant up --no-parallel`. De omgeving zal zichzelf volledig opzetten zowel het aanmaken van de VM's als het configureren van de verschillende functionaliteiten. Let op dit kan heel lang duren.

```powershell
PS C:\HOGENT\Schooljaar_2627\Windows Server II\WSII_Eindopdracht\src> vagrant up --no-parallel
Bringing machine 'server1' up with 'virtualbox' provider...
Bringing machine 'server2' up with 'virtualbox' provider...
Bringing machine 'server3' up with 'virtualbox' provider...
Bringing machine 'client' up with 'virtualbox' provider...
==> server1: Importing base box 'gusztavvargadr/windows-server-2025-standard-core'...
==> server1: Matching MAC address for NAT networking...
==> server1: Checking if box 'gusztavvargadr/windows-server-2025-standard-core' version '2607.0.0' is up to date...
==> server1: Setting the name of the VM: server1
==> server1: Clearing any previously set network interfaces...
==> server1: Preparing network interfaces based on configuration...
    server1: Adapter 1: nat
    server1: Adapter 2: hostonly
==> server1: Forwarding ports...
    server1: 3389 (guest) => 53389 (host) (adapter 1)
    server1: 5985 (guest) => 55985 (host) (adapter 1)
    server1: 5986 (guest) => 55986 (host) (adapter 1)
    server1: 22 (guest) => 2222 (host) (adapter 1)
==> server1: Running 'pre-boot' VM customizations...
==> server1: Booting VM...
==> server1: Waiting for machine to boot. This may take a few minutes...
    server1: WinRM address: 127.0.0.1:55985
    server1: WinRM username: vagrant
    server1: WinRM execution_time_limit: PT2H
    server1: WinRM transport: plaintext
==> server1: Machine booted and ready!
==> server1: Checking for guest additions in VM...
==> server1: Setting hostname...
==> server1: Waiting for machine to reboot...
==> server1: Mounting shared folders...
    server1: C:/HOGENT/Schooljaar_2627/Windows Server II/WSII_Eindopdracht/src => /vagrant
==> server1: Running provisioner: initial (shell)...
    server1: Running: script: initial
    server1:
    server1: === CONFIGURATIE FIREWALL ===
    server1:
    server1: [...] Firewallregel SSH (host + Vagrant NAT) wordt toegevoegd
    server1: [OK] Firewallregel 'SSH (host + Vagrant NAT)'
    server1: [...] Firewallregel Vagrant WinRM (NAT) wordt toegevoegd
    server1: [OK] Firewallregel 'Vagrant WinRM (NAT)'
    server1: [...] Firewallregel Beheer - WinRM wordt toegevoegd
    server1: [OK] Firewallregel 'Beheer - WinRM'
    server1: [...] Firewallregel Beheer - RPC Endpoint Mapper wordt toegevoegd
    server1: [OK] Firewallregel 'Beheer - RPC Endpoint Mapper'
    server1: [...] Firewallregel Beheer - RPC dynamisch wordt toegevoegd
    ....
```

5. Controleer de uitvoer.

Het is belanrgijk om de uitvoer te controleren op eventuele errors. De scripts zijn zo opgesteld dat het duidelijk is waar er eventueel een fout opduikt. Wanneer dit het geval is, is het belangrijk om de error goed te lezen en zelf eens op zoek te gaan waar in het script het juist fout loopt.

Je kan steeds de scripts manueel uitvoeren op de VM's, maar dan moet je wel met enkele zaken rekening houden:

- De volgorde van de scripts: eerst het **initial** script en dan pas het **Services** script
- De volgorde van de VM's: server1 -> server2 -> server3 -> client
- De VM moet na het **Initial** scripts steeds herstart worden.
- Schakel de afgewerkte VM's niet uit, de andere VM's zijn afhankelijk van de voorgaande

In het geval dat er helemaal geen error zijn, kan je gewoon doorgaan naar de volgende stap.

### 1.4 Testen van de omgeving

1. Open VirtualBox en start de GUI van de client.
2. Login met een admin gebruiker (Zie [Credentials](#32-overzicht-gebruikers)).

## 2. Status van het project

### 2.1 Wat is afgewerkt en wat nog niet?

Alle functionaliteiten die voor deel 1 aanwezig moeten zijn, zijn afgewerkt. Ik ben nog niet begonnen aan deel 2.

### 2.2 Welke problemen kwam je tegen, en hoe heb je deze opgelost?

Ik ben tijdens het uitvoeren van het project toch enkele problemen tegengekomen, de ene wat groter als de andere. Hieronder zal ik alle problemen opsommen en kort bespreken.

#### 2.2.1 Opsplisten verschillende scripts

Ik had gehoopt om elke VM volledig te kunnen configureren met één PowerShell-script, maar dit bleek niet echt mogelijk te zijn doordat de VM's opnieuw moesten opstarten wanneer deze aan het domein werd toegevoegd of werd gepromoveerd tot domeincontroller. Dit heb ik opgelost door per VM twee scripts op te stellen. Het eerste script is voor de initiële configuratie zoals firewalls, netwerkinstellingen en het toevoegen aan het domein. Na het uitvoeren van dit script kan de VM herstarten waarna het tweede script uitgevoerd kan worden. Dit script zorgde dan voor het installeren van de nodige rollen en het configureren van de verschillende functionaliteiten.

#### 2.2.2 Onvoldoende kennis

Het project bestond uit zaken die we reeds gezien hebben tijdens Windows Server I maar ook uit zaken die we nog niet gezien hadden. Dit kan wel voor wat moeilijkheden zorgen. Om deze zaken te onderzoeken heb ik voornamelijk gebruik gemaakt van enerzijds _Microsoft Learn_ en anderzijds _Microsoft Copilot_. _Microsoft Learn_ voorziet uitgebreide stappenplannen en info pagina's die helpen bij het configureren. _Copilot_ helpt je dan weer voornamelijk bij het troubleshooten van de omgeving. Door deze tools te gebruiken en zelf kritisch na te denken kom je al een hele eind.

#### 2.2.3 Rechten

Bij het schrijven bepaalde scripts kreeg ik soms een error die erop wees dat ik niet beschikte over de juist rechten aangezien het geconfigureerd werd door de vagrant user, maar deze is niet beschikbaar binnen het domein zelf. Dit heb ik kunenn oplossen door gebruik te maken van `Invoke-Command`. Hiermee kan je commando's uitvoeren als een andere user binnen hetzelfde scripts. Je moet dan wel bepaalde zaken meegeven zoals de credentials en op welke machine de commando's uitgevoerd moeten worden.

## 3. Conclusie

### 3.1 Wat heb je geleerd uit dit deel van het project?

Het is niet altijd even simpel om handmatige bewerkingen te automatiseren. Je moet steeds nadenken over wat er precies zal gebeuren bij elk lijntje code. Maar dit zorgt er wel voor dat je een dieper inzicht krijgt in de werking van de verschillende functionaliteiten. Ook heb je bij het schrijven van de scripts de volledige vrijheid in hoe je bepaalde zaken configureerd en hoe de structuur eruit ziet. Tijdens Windows Server I hadden we al heel wat zaken gezien over de verschillende rollen die er beschikbaar zijn. Maar we hebben niet al deze rollen steeds uitgewerkt via PowerShell. Het was dan ook niet altijd even evident om meteen het correcte commando te vinden. Ook waren er enkele zaken aanwezig zoals de Certificate Authority die we nog nooit gezien hadden. Dankzij dit project heb ik dus zeker op technisch vlak heel wat nieuwe zaken geleerd

### 3.2 Wat zou je in de toekomst anders doen?

Het enige wat ik de toekomst anders zou doen is het toevoegen van extra RAM-geheugen aan de client. De client VM is heel wat zwaarder als de server VM's waardoor het configureren ook wat meer tijd neemt. Dat is ook de reden dat ik deze VM 6GB heb toegekend. Op die manier kon ik toch wat beter werken op de client.

Voor de rest zou ik denk ik niet echt iets anders doen. Ik heb mezelf een stricte planning opgelegd waar ik me heb aan kunnen houden. Daarbij heb ik zo gestructureerd mogelijk te werk proberen gaan in mijn scripts.

### 3.3 Aan welke zaken heb je (te) veel tijd verloren?

Waar ik het meeste tijd aan verloren heb, is eigenlijk het testen van de omgeving. Windows VM's zijn jammer genoeg heel zwaar en eisen heel wat resources van het hostsysteem. Dit maakt dat het opzetten van de omgeving heel lang kan duren. Dus telkens wanneer er een nieuw stukje code geschreven wordt, moet de omgeving opnieuw opgezet worden om na te gaan of alles wel correct werkt. Dit is heel tijdrovend. Ik heb van collega's wel vernomen dat wanneer de omgeving wordt opgezet op een host met Linux als besturingssysteem alles veel sneller gaat.

Ik heb ook wel wat tijd verloren aan troubleshooting, maar dat is natuurlijk normaal aangezien er nieuwe zaken aan te pas kwamen. Moest alles van de eerste keer werken dan zou dat heel mooi zijn, maar dat is natuurlijk niet realistisch. En het hoort eenmaal bij de job als infrastructure engineer. Je leert er ook zaken uit dus of je dit eccht tijdsverlies kan noemen, laat ik in het midden.
