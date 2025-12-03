param (
    [bool]$setEnabled
)

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
        [bool]$setEnabled
    )
    if ($setEnabled -eq $false) {
        Write-Host "Disabling Modern Standby"
        Set-ItemProperty -Path $modernStandbyRegKeyPath -Name $modernStandbyRegKeyEntry -Value 0
    }
    if ($setEnabled -eq $true) {
        Write-Host "Enabling Modern Standby"
        Remove-ItemProperty -Path $modernStandbyRegKeyPath -Name $modernStandbyRegKeyEntry -ErrorAction SilentlyContinue
    }

}

# Output current status
get-modernStandbyStatus

if ($PSBoundParameters.ContainsKey('setEnabled')) {
    set-modernStandby -setEnabled $setEnabled
}
$setEnabled = $NULL
