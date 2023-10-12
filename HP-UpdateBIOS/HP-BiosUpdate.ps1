<#
    .NOTES
        Powershell script which uses the HP Image Assistant (HPIA) to manage Drivers and Firmware updates for HP PC.
        Prerequisites: 
            Microsoft Windows 10 64bit OS with HP Inc. designed PC platform, please refer to the site for details: https://ftp.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.html
            Download the HP CMSL installer from: https://ftp.ext.hp.com/pub/caps-softpaq/cmit/hp-cmsl.html and include in the same directory as the script.
            The script downloads and installs the HPIA (hp-hpia-5.1.3.exe) from: https://hpia.hpcloud.hp.com/downloads/hpia/hp-hpia-5.1.3.exe
            Please refer to the latest HPIA version relase in the site: https://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html
        
        Purpose: 
            Updates Drivers to latest version(s). 
        
        Important: 
            Ensure the HPIA version that is packaged with the script matches the version located in the variable section at the beginning of the script.
            The script will be set in c:\windows\temp\HPIA, with all of downloaded software package in c:\windows\temp\HPIA\Download, generated Report in c:\windows\temp\HPIA\Report, HPIA progressing logs in c:\windows\temp\HPIA\Logs\<computername>_HPIA.log
            All of HPIA technology details please refer to the site for details: https://ftp.hp.com/pub/caps-softpaq/cmit/whitepapers/HPIAUserGuide.pdf
            
        Usage: 
            Open a Powershell Admin prompt, navigate to the script and run the script with: "powershell -executionpolicy bypass -file HP-DriverUpdate.ps1 -action <action> -selection <selection>"
            Script must includes the mandatory parameters -action and -selection, otherwise script will exit. 
            There is an optional parameter -updateHPIA to get latest version HPIA from web site, when use this one the offline HPIA installer is not required to be with script, otherwise script will exit.
        Mandatory Parameters:
        -action
            Download: Download installers only
            Install: Download and install
        -selection
            All: Selects all recommendations available.
            Critical: This option selects all SoftPaqs with a ReleaseType of Critical.
            Recommended: This option selects all SoftPaqs with a ReleaseType of Recommended.
        
        Optional Parameters:
        -updateHPIA
        Example (Check all drivers including Critical, Recommended and Routine drivers, download and install them, by leveraging latest version HPIA):
        powershell -executionpolicy bypass -file HP-DriverUpdate.ps1 -action Install -selection all -updateHPIA
        Example (Check all of critical updates on Drivers and install them):
        powershell -executionpolicy bypass -file HP-DriverUpdate.ps1 -action Install -selection Critical
    
        Example (Check recommended updates on Drivers, but only download them):
        powershell -executionpolicy bypass -file HP-DriverUpdate.ps1 -action Download -selection Recommended
        Example (Check all drivers including Critical, Recommended and Routine drivers, download and install them):
        powershell -executionpolicy bypass -file HP-DriverUpdate.ps1 -action Install -selection ALL
#>

param(
        [parameter()][ValidateNotNullOrEmpty()] [string] $selection,
        [parameter()][ValidateNotNullOrEmpty()] [string] $action,
        [parameter()][ValidateNotNullOrEmpty()] [switch] $updateHPIA
)


#=============================================================
# EDIT VARIABLES HERE 
#=============================================================

$scriptversion = "1.0.6"

# System Variables

$timestamp = Get-Date -format "yyyyMMddTHHmmssffff"
$computerName = (Get-wmiobject win32_battery).SystemName + "_DriverUpdate_"+$timestamp+".log"
$logPath = "$env:Programdata\HP\HPDeviceManagement\Logs\HPIA"
$logFile = Join-Path $logpath $computername
$regTagPath = "HKLM:\SOFTWARE\HP\HPDeviceManagement\HPIA\DriverUpdate"
$ErrorActionPreference = "SilentlyContinue"

# HPIA Variables 

$hpiaversion = "5.1.9" # Modify here if needed
$hpiaout = "$PSScriptRoot\hp-hpia-5.1.9.exe"
$hpiainstallargs = "/s /e /f C:\ProgramData\HP\HPIA"
$hpiapath="C:\ProgramData\HP\HPIA\HPImageAssistant.exe"
$hpiauri = "https://hpia.hpcloud.hp.com/downloads/hpia/hp-hpia-5.1.9.exe"

# CMSL Variables 
$cmslInstallerVersion = "1.6.10"
$cmslOut = "$PSScriptRoot\hp-cmsl-$cmslInstallerVersion.exe"
$cmslUri = "https://hpia.hpcloud.hp.com/downloads/cmsl/hp-cmsl-$cmslInstallerVersion.exe"
$cmslCurrentVersion = 0
$cmslArgs = "/VERYSILENT"
$cmslRegPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{5A1AECCB-E0CE-4D2C-833C-29CCEA959448}_is1"

#---------------------------  START OF MAIN FUNCTIONS, DO NOT EDIT BELOW ------------------------------

#=============================================================
# Create HPIA Dump Path
#=============================================================

$subname = "HPIA"
$targetdir = Join-Path c:\windows\temp $subname
if(-not (Test-Path $targetdir)){
    New-Item -ItemType Directory -Path c:\windows\temp\HPIA\Logs -Force
    New-Item -ItemType Directory -Path c:\windows\temp\HPIA\Report -Force
}

#=============================================================
# Create Log Path
#=============================================================

if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path C:\Programdata\HP\HPDeviceManagement\Logs\HPIA -Force
}

function Write-Log {
    param($msg)
    "$(Get-Date -Format G) :$msg" | Out-File -FilePath $logfile -Append -Force
}

#=============================================================
# Create Logging Regkey
#=============================================================
function Add-RegistryHistory {
    try {

        if (!(Test-Path $regTagpath)) { New-Item -Path $regTagPath -Force }

        # The last date and time the Drivers update script was run regardless if it was successful or not
        $lastExecutionTime = Get-Date -format "MM/dd/yyyy HH:mm"
        Set-ItemProperty -Path $regTagPath -Name "LastExecutionTime" -Value $lastExecutionTime -ErrorAction $ErrorActionPreference -Force 
        [int]$dateTime = (Get-ItemProperty -Path $regTagPath -Name "DateTime" -ErrorAction $ErrorActionPreference).dateTime

        
        if ($dateTime) {
            $dateTime++
            Set-ItemProperty -Path $regTagPath -Name "DateTime" -Value $dateTime -Force
        }

        Set-ItemProperty -Path $regTagPath -Name "ExitCode" -Value "0" -Force
            
    }
    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception

        $ErrorMessage = $_.Exception
        $ExitCode = 343
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
    }
}

#=============================================================
# Create Logging Code
#=============================================================

function Add-RegistryCode {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $ExitCode, 
        [Parameter(Mandatory = $false)]
        [string] $ErrorMessage
    )

    if (!(Test-Path $regTagpath)) { New-Item -Path $regTagPath -Force }

    try {

        # create last execution time
        $lastExecutionTime = Get-Date -format "MM/dd/yyyy HH:mm"
        Set-ItemProperty -Path $regTagPath -Name "LastExecutionTime" -Value $lastExecutionTime -ErrorAction $ErrorActionPreference -Force 
        [int]$dateTime = (Get-ItemProperty -Path $regTagPath -Name "DateTime" -ErrorAction $ErrorActionPreference).dateTime

        if ($dateTime) {
            $dateTime++
            Set-ItemProperty -Path $regTagPath -Name "DateTime" -Value $dateTime -Force
        }

        # create error message if it exists
        if ($ErrorMessage) {
            New-ItemProperty -Path $regTagPath -Name "ErrorMessage" -Value $ErrorMessage -Force
        }

        # create exit code, if there is no error it will inpot "0"
        New-ItemProperty -Path $regTagPath -Name "ExitCode" -Value $ExitCode -Force
        # check if there was no errors
        if ($ExitCode -eq "") {
            Set-ItemProperty -Path $regTagPath -Name "ExitCode" -Value "0" -Force
        }
    }
    catch {
        Write-Host $_.Exception
    }
}


#=============================================================
# Clear Registry Values 
#=============================================================

function Clear-RegistryHistory {
    try {
        Remove-ItemProperty -Path $regTagPath -Name "ExitCode" -Force
        Remove-ItemProperty -Path $regTagPath -Name "ErrorMessage" -Force
    }
    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception
    }
}

#=============================================================
# Script parameter acceptance
#=============================================================

if(!($selection -and $action)){
    Write-Warning "The script requires mandatory parameter to specify Driver Update priority level(-selection <All|Critical|Recommended>) and action choice on seclected Driver Update package(-action <Download|Install>). Exiting script for now, please try again."
    $ErrorMessage = "The script requires mandatory parameter to specify Driver Update priority level(-selection <All|Critical|Recommended>) and action choice on seclected Driver Update package(-action <Download|Install>). Exiting script for now, please try again."
    $ExitCode = 343
    Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
    Exit 343
}
else{
 
    Switch ($selection){

        All {
		    Write-Host "Selection is All..."
            $selectionargs="/Selection:All"
        }
        Critical{
		    Write-Host "Selection is Critical..."
            $selectionargs="/Selection:Critical"
        }
        Recommended {
	        Write-Host "Selection is Recommended..."
            $selectionargs="/Selection:Recommended"
        }
        default {
            Write-Host "Selection is not defined."
        }
    }  
 
    Switch ($action){
        Download {
		    Write-Host "Beginning Download..."
            $actionargs="/Action:Download"
        }
        Install {
	        Write-Host "Beginning Install..."
            $actionargs="/Action:Install"  
        }
        default {
            Write-Host "Action is not defined."
        }
    }
}

if($selectionargs -and $actionargs){
    Write-Host "All parameters are defined correctly."
}
else {
    Write-Host "You must supply a valid value for -action and -selection, current parameter is invalid. Exiting script."
    $ErrorMessage = "You must supply a valid value for -action and -selection, current parameter is invalid. Exiting script."
    $ExitCode = 343
    Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
    Exit 343
}

#=============================================================
# Check if HP manufactured device
#=============================================================
function Check-HP-Device {
    
    $systemInfo = Get-WmiObject -Class Win32_ComputerSystem 
    $SystemBIOSInfo = get-wmiobject -class win32_bios 
    $ComputerInfo = Get-ComputerInfo
    $OSname = $ComputerInfo.OSname
    $CsSystemType = $ComputerInfo.CsSystemType
    $OsVersion = $ComputerInfo.OsVersion

    $PCManufacturer = $systemInfo.Manufacturer
    $PCModel = $systemInfo.model
    $PCSerialNumber = $systemBIOSInfo.SerialNumber
    $PCBIOSVersion = $systemBIOSInfo.SMBIOSBIOSVersion
    $PCName = $systemInfo.Name

    Write-Log "Your PC Manufacturer: $PCManufacturer"
    Write-Log  "Your PC Model: $PCModel"
    Write-Log  "Your PC SerialNumber: $PCSerialNumber"
    Write-Log  "Your PC BIOS Version: $PCBIOSVersion"
    Write-Log  "Your PC Name: $PCName"
    Write-Log  "Your PC OS: $OSname $CsSystemType $OsVersion"

    try {

        if (($SystemInfo.Manufacturer -like "*HP*") -or ($SystemInfo.Manufacturer -like "*Hewlett*")) {
            Write-Log "HP manufactured PC found."    
            Write-Host "HP manufactured PC found."
        }
        else {
            Write-Log "Script is only supported on HP manufactured PCs."
            Write-Host "Script is only supported on HP manufactured PCs."
            
            $ErrorMessage = "Script is only supported on HP manufactured PCs"
            $ExitCode = 8
            Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
            Add-RegistryHistory
            Exit 8
        }
    }
    catch {
        Write-Log $_.Exception.Message
        Write-Host $_.Exception.Message
        
        $ErrorMessage = $_.Exception.Message
        $ExitCode = 8
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory	
        Exit 8
    }
}

function Check-OS-BuildNumber {
    try {

        $OsVersion = (Get-WmiObject win32_OperatingSystem).BuildNumber
        $minVersion = "14393"
        
        if ($OsVersion -ge $minVersion) {
            Write-Log "Windows OS version is supported."
            Write-Host "Windows OS version is supported."
            #return $true
        }

        else {
            Write-Log "Windows OS version is not supported. Exiting script."
            Write-Host "Windows OS version is not supported. Exiting script."
            
			$ErrorMessage = "Windows OS version is not supported"
            $ExitCode = 27
            Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
            Exit 27
        }
    }
    catch {
        Write-Log $_.Exception.Message
        Write-Host $_.Exception.Message
        
		$ErrorMessage = $_.Exception.Message
        $ExitCode = 27
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Exit 27
    }
}

#=============================================================
# HPIA Functions
#=============================================================

function Install-localHPIA {
    try {
        Start-Process -Filepath $hpiaout -ArgumentList $hpiainstallargs -Wait
        
        Write-Log "HPIA is installed locally on this system. "
        Write-Host "HPIA is installed locally on this system."
    }
    catch {
        Write-Log $_.Exception
        
        
        $ErrorMessage = "HPIA installer not found"
        $ExitCode = 125
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
		Exit 125
    }
}

function Install-onlineHPIA{
    try {
            Install-HPImageAssistant -Extract -DestinationPath "C:\ProgramData\HP\HPIA" -quiet
            $HPIAversion = (Get-Item $hpiapath).VersionInfo.FileVersion
            Write-Log "HPIA has been updated in this system at version $HPIAversion."
            Write-Host "HPIA has been updated in this system at version $HPIAversion."        
        }
    catch {

        if ($_.Exception.GetType().Name -eq "CommandNotFoundException") {       
            Write-Log $_.Exception
        }

        $ErrorMessage = "HPIA installer not found"
        $ExitCode = 125
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Exit 125
    }
}

function Check-HPIA{
    try{
        if (Test-Path $hpiapath -PathType Leaf){
            $HPIAversion = (Get-Item $hpiapath).VersionInfo.FileVersion
            Write-Log "HPIA installed on this system is version $HPIAversion."
            Write-Host "HPIA installed on this system is version $HPIAversion."
            return $true
        }
        else{
            Write-Log "HPIA not installed on this system."
            Write-Host "HPIA not installed on this system."
            return $false
        }
    }
    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception
        
        $ErrorMessage = $_.Exception.Message
        $ExitCode = 343
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Exit 343
    }
}


#=============================================================
# CMSL Functions
#=============================================================

function Get-CMSL-Installer {

    try {
        if (Test-Path $cmslOut) {
            Write-Log "HP CMSL installer found."
            Write-Host "HP CMSL installer found."
        }
         else { 
            Write-Log "HP CMSL is not in the folder with script or has an incorrect name, please ensure the CMSL installer is downloaded and name of the file is correct."
            Write-Host "HP CMSL is not in the folder with script or has an incorrect name, please ensure the CMSL installer is downloaded and name of the file is correct."
            
			$ErrorMessage = "HP CMSL is not in the folder with script or has an incorrect name, please ensure the CMSL installer is downloaded and name of the file is correct"
            $ExitCode = 64
            Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
            #Exit 64
         }
        } 
        catch {
            Write-Log $_.Exception
            Write-Host $_.Exception
            
			$ErrorMessage = $_.Exception.Message
            $ExitCode = 64
            Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
            Add-RegistryHistory
			Exit 64
    }
        
}

function Check-CMSL-Version {
    try {

        $cmslCurrentVersion = (Get-ItemProperty -Path $cmslRegPath -ErrorAction $ErrorActionPreference).DisplayVersion 

        if ($cmslCurrentVersion -lt $cmslInstallerVersion) {
            return $false
        }
        else {
            return $true
        }
    }

    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception
        
		$ErrorMessage = $_.Exception.Message
        $ExitCode = 343
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory
        return $false
        
    }
}
 

function Check-CMSL-Install {
    
    try {

        if (Test-Path $cmslRegPath) {
            Write-Log "HP CMSL installed on this system."
            Write-Host "HP CMSL installed on this system."
            return $true
        }
            else { 
                Write-Log "HP CMSL is not installed on this system."
                Write-Host "HP CMSL is not installed on this system."
                return $false
        }
    }
    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception
        
		$ErrorMessage = $_.Exception.Message
        $ExitCode = 65
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory
		Exit 65
    }

}

function Download-CMSL {
        
    
    # Code for initializing network connection on installer, and preparing for downloading
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   
    try {
        
        if (!(Test-Path -Path $cmslOut -PathType Leaf)) {  
             
            [System.Net.WebClient]$client = New-Object System.Net.WebClient
            $client.DownloadFile($cmslUri, $cmslOut)
           
            if ($cmslOut) {
                Write-Log "HP CMSL successfully downloaded"
                Write-Host "HP CMSL successfully downloaded"
            }
       
        }
        else {
            Write-Log "HP CMSL installed on this system."
            Write-Host "HP CMSL installed on this system."
        }
    }
    catch {
        Write-Log $_.Exception
        Write-Host $_.Exception

        $ErrorMessage = $_.Exception.Message
        $ExitCode = 343
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory
		Exit 343
    }


}
function Install-CMSL {
   
    try {
        Start-Process -Filepath $cmslout -ArgumentList $cmslargs -Wait
        return $true | Out-Null

    }
    catch {
        if ($_.Exception.GetType().Name -eq "InvalidOperationException") {       
            return $false | Out-Null
        }
        Write-Log $_.Exception
        Write-Host $_.Exception
        
		$ErrorMessage = $_.Exception.Message
        $ExitCode = 65
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory
		Exit 65
    }    
}

#=============================================================
# Script commands start here
#=============================================================

# Clear previous registry history 
Clear-RegistryHistory

#Check-HP-Device
Check-OS-BuildNumber

$checkhpia = Check-HPIA

if($updateHPIA){

    if ($checkhpia){
        Write-Log "HPIA is installed on this system."
        Write-Host "HPIA is installed on this system."
    }
    else{

    # Validate CMSL Install
    $location = Get-CMSL-Installer
    $installed = Check-CMSL-Install
    
    if ($location -eq $false) {
        $ErrorMessage = "CMSL installer not found"
        $ExitCode = 64
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Exit 64
    }

    $retry = 3
    while ($installed -eq $false -and $retry -gt 0) {   
        Install-CMSL 
        Start-Sleep 20 
        $installed = Check-CMSL-Install
        $retry--
}

    if ($installed -eq $true) {
        Write-Log "HP CMSL successfully installed."
    }
    else {
        Write-Log "HP CMSL failed to install."
        Write-Host "HP CMSL failed to install."
        
        $ErrorMessage = "HP CMSL failed to install"
        $ExitCode = 65
        Add-RegistryCode -ExitCode $ExitCode -ErrorMessage $ErrorMessage
        Add-RegistryHistory
        Exit 65
    }
        Install-onlineHPIA
    }

}

else {

    if($checkhpia){
        Write-Log "HPIA is installed on this system."
        Write-Host "HPIA is installed on this system."
    }
    else{
            Install-localHPIA
        }
       
    }
    

$hpiaargs="/Operation:Analyze $Selectionargs $actionargs /Category:BIOS /silent /noninteractive /Debug /LogFolder:c:\windows\temp\HPIA\Logs /reportFolder:c:\windows\temp\HPIA\Report /softpaqdownloadfolder:c:\windows\temp\HPIA\Download"
Start-Process -Filepath $hpiapath -ArgumentList $hpiaargs -Wait
Write-Host "Your Drivers update package has successfully downloaded in C:\Windows\Temp\HPIA\Download"
Add-RegistryCode | Out-Null

shutdown /r /t 600 /c "El equipo se reiniciara en 10min por actualizacion de Bios, Guardar toda su informacion.  !ADVERTENCIA! No desconectar la corriente, ni apagar el equipo durante el proceso!"
timeout /t 10 /nobreak > nul

Exit
