# ==========================================
# ZONE DE CONFIGURATION (A MODIFIER)
# ==========================================

# 1. Configuration Système
$NouveauNomServeur = "SRV-AD01"

# 2. Configuration Réseau
$IPAddress         = "192.168.1.10"
$PrefixLength      = 24              # 24 équivaut au masque 255.255.255.0
$DefaultGateway    = "192.168.1.1"
$DNSServer         = "127.0.0.1"     # Toujours localhost pour un contrôleur de domaine
$NomInterfaceActuelle = "Ethernet0"  # Vérifiez avec Get-NetAdapter si différent
$NouveauNomInterface  = "LAN"

# 3. Configuration Active Directory
$DomainNameDNS     = "mondomaine.local"
$DomainNameNetbios = "MONDOMAINE"
$CheminBaseDeDonnees = "C:\Windows\NTDS"
$CheminSYSVOL        = "C:\Windows\SYSVOL"

# ==========================================
# FIN DE LA CONFIGURATION
# ==========================================

Write-Host "--- Début de la procédure de déploiement ---" -ForegroundColor Cyan

# --- ETAPE 1 : Configuration Réseau ---
Write-Host "1. Configuration de l'adresse IP..." -ForegroundColor Yellow
try {
    # On renomme la carte réseau pour plus de clarté
    Rename-NetAdapter -Name $NomInterfaceActuelle -NewName $NouveauNomInterface -ErrorAction SilentlyContinue
    
    # Récupération de l'index de l'interface
    $InterfaceIndex = (Get-NetAdapter -Name $NouveauNomInterface).ifIndex

    # Vérification si l'IP existe déjà pour éviter les erreurs
    if (-not (Get-NetIPAddress -IPAddress $IPAddress -ErrorAction SilentlyContinue)) {
        New-NetIPAddress -IPAddress $IPAddress -PrefixLength $PrefixLength -InterfaceIndex $InterfaceIndex -DefaultGateway $DefaultGateway
        Write-Host "Adresse IP configurée." -ForegroundColor Green
    } else {
        Write-Host "Adresse IP déjà configurée (ou inchangée)." -ForegroundColor Gray
    }

    # Configuration du DNS
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses ($DNSServer)
    Write-Host "DNS configuré." -ForegroundColor Green
}
catch {
    Write-Error "Erreur non bloquante ou réseau déjà configuré. On continue..."
}

# --- ETAPE 2 : Renommage du Serveur ---
Write-Host "2. Vérification du nom du serveur..." -ForegroundColor Yellow
$CurrentName = $env:COMPUTERNAME

if ($CurrentName -ne $NouveauNomServeur) {
    Write-Host "Le nom actuel ($CurrentName) est différent du nom cible ($NouveauNomServeur)."
    Rename-Computer -NewName $NouveauNomServeur -Force
    
    Write-Warning "==============================================================="
    Write-Warning "LE SERVEUR A ETE RENOMME."
    Write-Warning "VEUILLEZ REDEMARRER LE SERVEUR MAINTENANT."
    Write-Warning "Une fois redémarré, relancez ce script pour finir l'installation."
    Write-Warning "==============================================================="
    return # Arrête le script ici
}
else {
    Write-Host "Le nom du serveur est correct ($CurrentName). Poursuite du script..." -ForegroundColor Green
}

# --- ETAPE 3 : Installation des Rôles ---
Write-Host "3. Installation des rôles AD DS et DNS..." -ForegroundColor Yellow
$FeatureList = @("RSAT-AD-Tools", "AD-Domain-Services", "DNS")

foreach ($Feature in $FeatureList) {
    if ((Get-WindowsFeature -Name $Feature).InstallState -ne "Installed") {
        Install-WindowsFeature -Name $Feature -IncludeManagementTools -IncludeAllSubFeature
        Write-Host "Rôle $Feature installé." -ForegroundColor Green
    }
    else {
        Write-Host "Rôle $Feature est déjà présent (InstallState: Installed)." -ForegroundColor Gray
    }
}

# --- ETAPE 4 : Promotion du Contrôleur de Domaine ---
Write-Host "4. Préparation de la promotion Active Directory..." -ForegroundColor Yellow

# CORRECTION : On vérifie le DomainRole via WMI au lieu du service
# 0-1 = Workstation, 2-3 = Server, 4-5 = Domain Controller
$SystemInfo = Get-CimInstance Win32_ComputerSystem
if ($SystemInfo.DomainRole -ge 4) {
    Write-Warning "Ce serveur est DÉJÀ un Contrôleur de Domaine (DomainRole 4 ou 5) !"
    Write-Warning "Arrêt du script pour éviter une erreur."
    Break
}

Write-Host "Le serveur est prêt à être promu." -ForegroundColor Green

# Demande du mot de passe de restauration (DSRM) de manière sécurisée
Write-Host "Veuillez saisir le mot de passe de restauration (DSRM) pour le futur domaine :" -ForegroundColor Cyan
$SafeModePwd = Read-Host -AsSecureString

$ForestConfiguration = @{
    '-DatabasePath'         = $CheminBaseDeDonnees;
    '-DomainMode'           = 'Default';
    '-DomainName'           = $DomainNameDNS;
    '-DomainNetbiosName'    = $DomainNameNetbios;
    '-ForestMode'           = 'Default';
    '-InstallDns'           = $true;
    '-LogPath'              = $CheminBaseDeDonnees;
    '-NoRebootOnCompletion' = $false; # Le serveur redémarrera automatiquement
    '-SysvolPath'           = $CheminSYSVOL;
    '-Force'                = $true;
    '-SafeModeAdministratorPassword' = $SafeModePwd;
}

Write-Host "Lancement de la création de la forêt... Le serveur redémarrera automatiquement à la fin." -ForegroundColor Magenta

Import-Module ADDSDeployment

try {
    Install-ADDSForest @ForestConfiguration
}
catch {
    Write-Error "Une erreur est survenue lors de la promotion : $_"
}
