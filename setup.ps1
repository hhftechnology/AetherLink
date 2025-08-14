# AetherLink Setup Script for Windows
# Run this script in PowerShell as Administrator

param(
    [switch]$Server,
    [switch]$Client,
    [switch]$Force
)

# Configuration
$InstallDir = "$env:LOCALAPPDATA\AetherLink"
$ConfigDir = "$env:APPDATA\AetherLink"
$GithubRepo = "hhftechnology/AetherLink"
$BinaryName = "aetherlink.exe"

# Colors
function Write-Success {
    param($Message)
    Write-Host "✓ " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Error {
    param($Message)
    Write-Host "✗ " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Info {
    param($Message)
    Write-Host "ℹ " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Print-Header {
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "                 AetherLink Setup Script                 " -ForegroundColor Blue
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-AetherLink {
    Write-Info "Installing AetherLink for Windows..."
    
    # Create installation directory
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    
    # Download latest release
    $downloadUrl = "https://github.com/$GithubRepo/releases/latest/download/aetherlink-windows.exe"
    $installPath = Join-Path $InstallDir $BinaryName
    
    Write-Info "Downloading from $downloadUrl..."
    
    try {
        # Enable TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Download with progress
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadProgressChanged += {
            Write-Progress -Activity "Downloading AetherLink" -PercentComplete $_.ProgressPercentage
        }
        
        $webClient.DownloadFile($downloadUrl, $installPath)
        Write-Progress -Activity "Downloading AetherLink" -Completed
        
        Write-Success "AetherLink downloaded successfully"
    }
    catch {
        Write-Error "Failed to download AetherLink: $_"
        exit 1
    }
}

function Add-ToPath {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentPath -notlike "*$InstallDir*") {
        Write-Info "Adding AetherLink to PATH..."
        
        $newPath = "$currentPath;$InstallDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        
        # Update current session
        $env:Path = "$env:Path;$InstallDir"
        
        Write-Success "Added to PATH"
    } else {
        Write-Info "AetherLink already in PATH"
    }
}

function Initialize-AetherLink {
    Write-Info "Initializing AetherLink..."
    
    # Create config directory
    if (!(Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    
    # Check if already initialized
    $configFile = Join-Path $ConfigDir "config.toml"
    if ((Test-Path $configFile) -and !$Force) {
        Write-Info "AetherLink already initialized (use -Force to reinitialize)"
    } else {
        & "$InstallDir\$BinaryName" init
        Write-Success "AetherLink initialized"
    }
    
    # Get Node ID
    $nodeIdOutput = & "$InstallDir\$BinaryName" info 2>&1
    $nodeId = ($nodeIdOutput | Select-String "Node ID: (.+)").Matches[0].Groups[1].Value
    
    Write-Host
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "Your Node ID: " -NoNewline
    Write-Host $nodeId -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    
    return $nodeId
}

function Setup-Server {
    Write-Info "Setting up AetherLink as server..."
    
    # Create Windows service (requires admin)
    if (Test-Administrator) {
        $createService = Read-Host "Would you like to install as a Windows service? (y/n)"
        if ($createService -eq 'y') {
            Install-WindowsService
        }
    } else {
        Write-Info "Run as Administrator to install as Windows service"
    }
    
    Write-Success "Server setup complete!"
    Write-Host
    Write-Host "To start the server manually, run:"
    Write-Host "  aetherlink server" -ForegroundColor Cyan
    Write-Host
    Write-Host "To authorize clients, run:"
    Write-Host "  aetherlink authorize <client-node-id>" -ForegroundColor Cyan
}

function Setup-Client {
    param($NodeId)
    
    Write-Info "Setting up AetherLink as client..."
    
    $serverId = Read-Host "Enter your server's Node ID"
    $serverName = Read-Host "Enter a name for this server (e.g., 'myserver')"
    
    & "$InstallDir\$BinaryName" add-server $serverName $serverId
    
    Write-Success "Server '$serverName' added"
    Write-Host
    Write-Host "Your client Node ID is: $NodeId" -ForegroundColor Yellow
    Write-Host "Give this to your server administrator to authorize your connection."
    Write-Host
    Write-Host "Once authorized, create a tunnel with:"
    Write-Host "  aetherlink tunnel <domain> --local-port <port> --server $serverName" -ForegroundColor Cyan
}

function Install-WindowsService {
    Write-Info "Installing Windows service..."
    
    $serviceName = "AetherLink"
    $serviceDisplayName = "AetherLink Tunnel Server"
    $serviceDescription = "AetherLink P2P tunnel server"
    $exePath = Join-Path $InstallDir $BinaryName
    
    # Check if service exists
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Info "Service already exists. Updating..."
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $serviceName
    }
    
    # Create service using nssm (if available) or sc.exe
    $nssmPath = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmPath) {
        & nssm install $serviceName $exePath server
        & nssm set $serviceName AppDirectory $InstallDir
        & nssm set $serviceName Description $serviceDescription
        & nssm set $serviceName Start SERVICE_AUTO_START
    } else {
        # Use sc.exe as fallback
        & sc.exe create $serviceName binPath= "$exePath server" DisplayName= $serviceDisplayName start= auto
        & sc.exe description $serviceName $serviceDescription
    }
    
    Write-Success "Windows service installed"
    Write-Host
    Write-Host "To start the service:"
    Write-Host "  Start-Service AetherLink" -ForegroundColor Cyan
    Write-Host "Or use Services management console (services.msc)"
}

function Create-DesktopShortcut {
    Write-Info "Creating desktop shortcut..."
    
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "AetherLink.lnk"
    
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-NoExit -Command `"& '$InstallDir\$BinaryName' --help`""
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.IconLocation = Join-Path $InstallDir $BinaryName
    $Shortcut.Description = "AetherLink Tunnel Manager"
    $Shortcut.Save()
    
    Write-Success "Desktop shortcut created"
}

# Main installation flow
function Main {
    Print-Header
    
    # Check Windows version
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Warning "AetherLink works best on Windows 10 or later"
    }
    
    # Install AetherLink
    Install-AetherLink
    
    # Add to PATH
    Add-ToPath
    
    # Initialize
    $nodeId = Initialize-AetherLink
    
    # Determine role
    if (!$Server -and !$Client) {
        Write-Host
        Write-Host "How will you use AetherLink?"
        Write-Host "1) As a server (accept incoming tunnels)"
        Write-Host "2) As a client (create tunnels to a server)"
        Write-Host "3) Both"
        Write-Host
        $choice = Read-Host "Enter choice (1-3)"
        
        switch ($choice) {
            "1" { $Server = $true }
            "2" { $Client = $true }
            "3" { $Server = $true; $Client = $true }
        }
    }
    
    # Setup based on role
    if ($Server) {
        Setup-Server
    }
    
    if ($Client) {
        Setup-Client -NodeId $nodeId
    }
    
    # Create desktop shortcut
    $createShortcut = Read-Host "Create desktop shortcut? (y/n)"
    if ($createShortcut -eq 'y') {
        Create-DesktopShortcut
    }
    
    # Final message
    Write-Host
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "          AetherLink Installation Complete!             " -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host
    Write-Host "Quick command reference:"
    Write-Host "  aetherlink --help                    # Show help"
    Write-Host "  aetherlink info                      # Show your Node ID"
    Write-Host "  aetherlink server                    # Start server"
    Write-Host "  aetherlink tunnel <domain> --local-port <port> --server <n>"
    Write-Host
    Write-Host "Installation directory: $InstallDir"
    Write-Host "Configuration directory: $ConfigDir"
    Write-Host
    Write-Host "For more information, see:"
    Write-Host "  https://github.com/$GithubRepo" -ForegroundColor Cyan
    Write-Host
    Write-Info "You may need to restart your terminal for PATH changes to take effect"
}

# Run main function
Main