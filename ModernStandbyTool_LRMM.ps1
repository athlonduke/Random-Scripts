#param (
#    [bool]$setEnabled
#)

$setEnabled = {{setEnabled}}

$powercfg = & "powercfg.exe" /a
$modernStandbyRegKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
$modernStandbyRegKeyEntry = "PlatformAoAcOverride"

if ($powercfg -like "*Standby (S3)*") {
    write-output "S3 supported"
} else {
    write-output "S3 not supported"
}

function get-modernStandbyStatus {
    if (Test-Path -path $modernStandbyRegKeyPath) {
        $modernStandbyRegEntry = Get-ItemProperty -Path $modernStandbyRegKeyPath -Name $modernStandbyRegKeyEntry -ErrorAction SilentlyContinue
        if ($modernStandbyRegEntry) {
            $currentValue = Get-ItemProperty -Path $modernStandbyRegKeyPath | Select-Object -ExpandProperty $modernStandbyRegKeyEntry -ErrorAction SilentlyContinue
            #Write-Host "Path exists - Entry exists - Current Value: " $currentValue
            if ($currentValue -eq 0) {
                Write-Host "Modern Standby is DISABLED"
            }
        } else {
            Write-Host "Modern Standby is ENABLED"
        }
    } else {
        write-host "Path not found!"
    }
}

function set-modernStandby {
    param(
        [int]$setEnabled
    )
    if ($setEnabled -eq 0) {
        Set-ItemProperty -Path $modernStandbyRegKeyPath -Name $modernStandbyRegKeyEntry -Value 0
        Write-Host "Modern Standby Disabled"
    }
    if ($setEnabled -eq 1) {
        Remove-ItemProperty -Path $modernStandbyRegKeyPath -Name $modernStandbyRegKeyEntry -ErrorAction SilentlyContinue
        Write-Host "Modern Standby Enabled"
    }

}

# Output current status
get-modernStandbyStatus

# Debug code
# Write-Host "set enabled: " $setEnabled

if ($setEnabled -eq 1) {
    Write-Host "Enabling Modern Authenication (you monster)"
    set-modernStandby -setEnabled $setEnabled
} elseif ($setEnabled -eq 0) {
    Write-Host "Disabling Modern Authentication"
    set-modernStandby -setEnabled $setEnabled
} else {
    Write-Host "No change request detected, ending script"
}
$setEnabled = $NULL
