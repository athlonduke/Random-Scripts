param (
    [bool]$setEnabled
)

$OneDrivePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
$OneDrivePathEntry = "DisableFileSync"

function get-OnDriveConfig {
    if (Test-Path -path $OneDrivePath) {
#        $OneDrivePath = Get-ItemProperty -Path $OneDrivePath -Name $OneDrivePathEntry -ErrorAction SilentlyContinue
        $currentValue = Get-ItemProperty -Path $OneDrivePath | Select-Object -ExpandProperty $OneDrivePathEntry -ErrorAction SilentlyContinue
        #Write-Host "Path exists - Entry exists - Current Value: " $currentValue
        if ($null -eq $currentValue) {
            Write-Host "OneDrive syncing is ENABLED"
        } else {
            Write-Host "OneDrive syncing is DISABLED"
        }
    } else {
        write-host "Path not found, OneDrive syncing is ENABLED!"
    }
}

function set-OneDriveSync ([int]$OneDriveFlag){
    #if set to 1, write the key and set to 1
    if ($OneDriveFlag -eq 1) {
        Write-Host "Disabling OneDrive sync. Please Reboot ASAP"
        New-Item -Path $OneDrivePath -Force
        Set-ItemProperty -Path $OneDrivePath -Name $OneDrivePathEntry -Value 1
    }
    # if set to 2, delete the value
    if ($OneDriveFlag -eq 2) {
        Write-Host "Enabling OneDrive sync"
        Remove-ItemProperty -Path $OneDrivePath -Name $OneDrivePathEntry -ErrorAction SilentlyContinue
    }

}

# Output current status
get-OnDriveConfig

$OneDriveStatusFlag = {{OneDriveStatusFlag}}

if ($OneDriveStatusFlag -ne 0) {
    set-OneDriveSync ($OneDriveStatusFlag)
}
