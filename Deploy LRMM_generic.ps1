[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$sitecode = $args[0]

$siteKey = "YOUR KEY HERE"

# build argument string
$arguments = "--action install --key $siteKey"

if ($sitecode) {
    $arguments = $arguments + ":" + $sitecode
}

#Check for Temp folder
if (Test-Path c:\temp) {
    Write-Host "C:\Temp found"
} else {
    Write-Host "Temp not found: creating c:\temp"
    mkdir c:\Temp
}

#Check for Existing Level RMM Installer
if ((Test-Path c:\temp\level-windows-amd64.exe) -eq "True") {
    Write-Host "--Removing the existing LRMM Installer"
    Remove-Item -path c:\temp\level-windows-amd64.exe
}

Write-Host ""
Write-Host "Downloading Level RMM Installer"
Invoke-WebRequest -Uri "https://downloads.level.io/stable/level-windows-amd64.exe" -OutFile c:\temp\level-windows-amd64.exe
if ((Test-Path c:\temp\level-windows-amd64.exe) -eq "True") {
    Write-Host "--Level RMM Installer Downloaded Successfully"
}
else {
    Write-Host "--Level RMM Installer Did Not Download - Please check Firewall or Web Filter"
    Stop-Transcript
    Exit 1
}

# starting installer
# final arguments
write-host ""
Write-Host "Final aguments:"
Write-Host $arguments
start-process c:\temp\level-windows-amd64.exe $arguments
