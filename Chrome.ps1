# Cambiar al directorio donde se encuentra el script
Set-Location -Path "C:/Temp"

# Ejecutar el script Deploy-GoogleChrome.ps1
Powershell.exe -ExecutionPolicy Bypass .\Deploy-GoogleChrome.ps1 -DeploymentType "Install" -DeployMode "Silent"