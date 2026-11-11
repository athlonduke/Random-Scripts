#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reports wear level (percent used) and power-on time for every physical drive.

.DESCRIPTION
    Wear is expressed as percent of rated life consumed: 0% = new, 100% = rated life used up.
    Each drive is polled with up to four methods, in this order, and the first one that
    returns a usable value wins. The "Source" column shows which one was used.

      1. NVMe-Log    NVMe SMART/Health log read directly from the drive (Percentage Used field).
      2. SMART-<id>  Raw ATA SMART attributes from WMI (root\wmi), for SATA SSDs.
      3. smartctl    smartmontools, if smartctl.exe is installed (optional).
      4. Counter     Get-StorageReliabilityCounter (often returns 0 when the drive reports nothing).

    Spinning hard drives have no wear figure and show N/A.

.NOTES
    Requires an elevated PowerShell session. Windows 10 / Server 2016 or later for method 1.
#>

# ---------------- Thresholds (edit these) ----------------
$WearWarningThreshold  = 75     # percent; wear ABOVE this value is flagged WARNING
$WearCriticalThreshold = 90     # percent; wear ABOVE this value is flagged WARNING (CRITICAL)
# ---------------------------------------------------------

$HoursPerYear = 8760            # 365 days

# SATA SMART attributes whose normalized value is "percent life remaining" (100 = new).
# Checked in this order; first one present on the drive is used.
$SmartLifeRemainingIds = 231, 202, 233, 177, 169, 230
#   231 SSD Life Left (Kingston, SandForce, many others)
#   202 Percent Lifetime Remaining (Crucial / Micron)
#   233 Media Wearout Indicator (Intel and others)
#   177 Wear Leveling Count (Samsung)
#   169 Remaining Life Percentage (Phison / Realtek based drives)
#   230 Media Wearout Indicator (WD / SanDisk)

# ======================================================================
# Method 1: NVMe SMART/Health log via IOCTL_STORAGE_QUERY_PROPERTY
# ======================================================================
if (-not ('DriveWear.Nvme' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace DriveWear {
    public static class Nvme {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
            byte[] inBuffer, int inSize, byte[] outBuffer, int outSize,
            out int returned, IntPtr overlapped);

        // Returns the 512-byte NVMe SMART/Health log page, or null if unavailable.
        public static byte[] GetHealthLog(int diskNumber) {
            const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
            const int HeaderSize = 8;     // STORAGE_PROPERTY_QUERY up to AdditionalParameters
            const int ProtoSize  = 40;    // STORAGE_PROTOCOL_SPECIFIC_DATA
            const int LogSize    = 512;
            int total = HeaderSize + ProtoSize + LogSize;

            using (SafeFileHandle h = CreateFile(@"\\.\PhysicalDrive" + diskNumber, 0, 3,
                                                 IntPtr.Zero, 3, 0, IntPtr.Zero)) {
                if (h.IsInvalid) return null;

                byte[] inBuf = new byte[total];
                byte[] outBuf = new byte[total];
                Put(inBuf, 0, 50);                    // PropertyId  = StorageDeviceProtocolSpecificProperty
                Put(inBuf, 4, 0);                     // QueryType   = PropertyStandardQuery
                Put(inBuf, HeaderSize + 0, 3);        // ProtocolType = ProtocolTypeNvme
                Put(inBuf, HeaderSize + 4, 2);        // DataType     = NVMeDataTypeLogPage
                Put(inBuf, HeaderSize + 8, 2);        // RequestValue = SMART/Health log (02h)
                Put(inBuf, HeaderSize + 12, 0);       // RequestSubValue
                Put(inBuf, HeaderSize + 16, ProtoSize); // ProtocolDataOffset
                Put(inBuf, HeaderSize + 20, LogSize);   // ProtocolDataLength

                int returned;
                if (!DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, inBuf, total,
                                     outBuf, total, out returned, IntPtr.Zero)) return null;

                int offset = HeaderSize + BitConverter.ToInt32(outBuf, HeaderSize + 16);
                int length = BitConverter.ToInt32(outBuf, HeaderSize + 20);
                if (length < LogSize || offset < 0 || offset + LogSize > returned) return null;

                byte[] log = new byte[LogSize];
                Array.Copy(outBuf, offset, log, 0, LogSize);
                return log;
            }
        }

        static void Put(byte[] buffer, int offset, int value) {
            BitConverter.GetBytes(value).CopyTo(buffer, offset);
        }
    }
}
'@
}

function Get-NvmeHealth {
    param([int]$DiskNumber)
    try   { $log = [DriveWear.Nvme]::GetHealthLog($DiskNumber) }
    catch { $log = $null }
    if (-not $log) { return $null }
    [pscustomobject]@{
        Wear  = [int]$log[5]                              # Percentage Used (can exceed 100)
        Hours = [int64][BitConverter]::ToUInt64($log, 128) # Power On Hours (low 64 bits)
    }
}

# ======================================================================
# Method 2: raw ATA SMART attributes from WMI (SATA drives)
# ======================================================================
$smartData  = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue)
$win32Disks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue)

function Get-AtaSmart {
    param([int]$DiskNumber)

    $w32 = $win32Disks | Where-Object { $_.Index -eq $DiskNumber } | Select-Object -First 1
    if (-not $w32 -or -not $w32.PNPDeviceID) { return $null }

    # WMI instance name is the PNP device ID with an instance suffix such as "_0"
    $entry = $smartData |
        Where-Object { $_.InstanceName -like ($w32.PNPDeviceID.Replace('[', '`[').Replace(']', '`]') + '*') } |
        Select-Object -First 1
    if (-not $entry -or -not $entry.VendorSpecific) { return $null }

    # 512-byte block: 2-byte revision, then 30 entries of 12 bytes:
    # [0] id, [1-2] flags, [3] normalized value, [4] worst, [5-10] raw, [11] reserved
    $bytes = [byte[]]$entry.VendorSpecific
    $attrs = @{}
    for ($i = 2; $i -le 350; $i += 12) {
        $id = $bytes[$i]
        if ($id -eq 0) { continue }
        $attrs[[int]$id] = [pscustomobject]@{
            Value = [int]$bytes[$i + 3]
            Raw32 = [int64][BitConverter]::ToUInt32($bytes, $i + 5)
        }
    }
    if ($attrs.Count -eq 0) { return $null }

    $wear = $null; $source = $null
    foreach ($id in $SmartLifeRemainingIds) {
        if ($attrs.ContainsKey($id) -and $attrs[$id].Value -ge 0 -and $attrs[$id].Value -le 100) {
            $wear   = 100 - $attrs[$id].Value
            $source = "SMART-$id"
            break
        }
    }

    $hours = $null
    if ($attrs.ContainsKey(9)) { $hours = $attrs[9].Raw32 }

    [pscustomobject]@{ Wear = $wear; Hours = $hours; Source = $source }
}

# ======================================================================
# Method 3: smartctl (smartmontools), only if installed
# ======================================================================
$smartctl = $null
$cmd = Get-Command smartctl.exe -ErrorAction SilentlyContinue
if ($cmd) { $smartctl = $cmd.Source }
elseif (Test-Path "$env:ProgramFiles\smartmontools\bin\smartctl.exe") {
    $smartctl = "$env:ProgramFiles\smartmontools\bin\smartctl.exe"
}

function Get-SmartctlHealth {
    param([int]$DiskNumber)
    if (-not $smartctl) { return $null }
    try   { $j = (& $smartctl -a -j "/dev/pd$DiskNumber" 2>$null | Out-String) | ConvertFrom-Json }
    catch { return $null }
    if (-not $j) { return $null }

    $wear = $null
    if ($j.nvme_smart_health_information_log -and $null -ne $j.nvme_smart_health_information_log.percentage_used) {
        $wear = [int]$j.nvme_smart_health_information_log.percentage_used
    }
    elseif ($j.endurance_used -and $null -ne $j.endurance_used.current_percent) {
        $wear = [int]$j.endurance_used.current_percent
    }
    elseif ($j.ata_smart_attributes -and $j.ata_smart_attributes.table) {
        foreach ($id in $SmartLifeRemainingIds) {
            $a = $j.ata_smart_attributes.table | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if ($a -and $a.value -ge 0 -and $a.value -le 100) { $wear = 100 - [int]$a.value; break }
        }
    }

    $hours = $null
    if ($j.power_on_time -and $null -ne $j.power_on_time.hours) { $hours = [int64]$j.power_on_time.hours }

    [pscustomobject]@{ Wear = $wear; Hours = $hours }
}

# ======================================================================
# Poll every drive
# ======================================================================
$report = foreach ($disk in Get-PhysicalDisk | Sort-Object { [int]$_.DeviceId }) {

    $num    = [int]$disk.DeviceId
    $isHdd  = ($disk.MediaType -eq 'HDD')
    $wear   = $null
    $hours  = $null
    $source = $null

    # 1. NVMe health log
    $nvme = Get-NvmeHealth -DiskNumber $num
    if ($nvme) { $wear = $nvme.Wear; $hours = $nvme.Hours; $source = 'NVMe-Log' }

    # 2. ATA SMART attributes
    if ($null -eq $wear -or $null -eq $hours) {
        $ata = Get-AtaSmart -DiskNumber $num
        if ($ata) {
            if ($null -eq $wear -and $null -ne $ata.Wear -and -not $isHdd) { $wear = $ata.Wear; $source = $ata.Source }
            if ($null -eq $hours -and $null -ne $ata.Hours) { $hours = $ata.Hours }
        }
    }

    # 3. smartctl
    if ($null -eq $wear -or $null -eq $hours) {
        $sc = Get-SmartctlHealth -DiskNumber $num
        if ($sc) {
            if ($null -eq $wear -and $null -ne $sc.Wear -and -not $isHdd) { $wear = $sc.Wear; $source = 'smartctl' }
            if ($null -eq $hours -and $null -ne $sc.Hours) { $hours = $sc.Hours }
        }
    }

    # 4. Storage reliability counter (last resort; a 0 here may mean "not reported")
    if ($null -eq $wear -or $null -eq $hours) {
        $rc = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($rc) {
            if ($null -eq $wear -and $null -ne $rc.Wear -and -not $isHdd) {
                $wear = [int]$rc.Wear
                $source = if ($wear -eq 0) { 'Counter (unverified)' } else { 'Counter' }
            }
            if ($null -eq $hours -and $null -ne $rc.PowerOnHours) { $hours = [int64]$rc.PowerOnHours }
        }
    }

    # --- Power-on time ---
    if ($null -ne $hours) {
        $years   = [math]::Floor($hours / $HoursPerYear)
        $days    = [math]::Floor(($hours % $HoursPerYear) / 24)
        $hoursTx = '{0:N0}' -f $hours
        $ageTx   = '{0}y {1}d' -f $years, $days
    } else {
        $hoursTx = 'N/A'
        $ageTx   = 'N/A'
    }

    # --- Status ---
    if ($null -eq $wear)                      { $status = 'N/A (not reported)' }
    elseif ($wear -gt $WearCriticalThreshold) { $status = 'WARNING (CRITICAL)' }
    elseif ($wear -gt $WearWarningThreshold)  { $status = 'WARNING' }
    else                                      { $status = 'OK' }

    [pscustomobject]@{
        Disk         = $disk.DeviceId
        Model        = $disk.FriendlyName
        Serial       = "$($disk.SerialNumber)".Trim()
        Type         = $disk.MediaType
        Bus          = $disk.BusType
        SizeGB       = [math]::Round($disk.Size / 1GB, 0)
        WearPercent  = if ($null -ne $wear) { "$wear%" } else { 'N/A' }
        Source       = if ($source) { $source } else { '-' }
        PowerOnHours = $hoursTx
        PowerOnAge   = $ageTx
        Status       = $status
        WearValue    = $wear        # numeric, for sorting/exporting; hidden from the table below
    }
}

# ======================================================================
# Output
# ======================================================================
Write-Host ''
Write-Host "Drive wear report for $env:COMPUTERNAME  (warning: wear > $WearWarningThreshold%, critical: wear > $WearCriticalThreshold%)"

$report |
    Format-Table Disk, Model, Serial, Type, Bus, SizeGB, WearPercent, Source, PowerOnHours, PowerOnAge, Status -AutoSize |
    Out-String -Width 300 |
    Write-Host

$flagged  = @($report | Where-Object { $_.Status -like 'WARNING*' })
$critical = @($flagged | Where-Object { $_.Status -eq 'WARNING (CRITICAL)' })

foreach ($d in $flagged) {
    if ($d.Status -eq 'WARNING (CRITICAL)') {
        Write-Host ("WARNING (CRITICAL): Disk {0} ({1}, S/N {2}) wear is {3}, above the {4}% critical threshold." -f `
            $d.Disk, $d.Model, $d.Serial, $d.WearPercent, $WearCriticalThreshold) -ForegroundColor Red
    } else {
        Write-Host ("WARNING: Disk {0} ({1}, S/N {2}) wear is {3}, above the {4}% warning threshold." -f `
            $d.Disk, $d.Model, $d.Serial, $d.WearPercent, $WearWarningThreshold) -ForegroundColor Yellow
    }
}

if ($flagged.Count -eq 0) {
    Write-Host "No drives above the $WearWarningThreshold% wear threshold." -ForegroundColor Green
}

if (-not $smartctl -and @($report | Where-Object { $_.Source -in '-', 'Counter (unverified)' -and $_.Type -ne 'HDD' }).Count -gt 0) {
    Write-Host "Note: some drives gave no verifiable wear figure. Installing smartmontools (smartctl) adds another polling method." -ForegroundColor Yellow
}

# Exit code: 2 if any drive is over the critical threshold, 1 if any is over the warning
# threshold, otherwise 0 (useful for RMM / scheduled tasks)
if ($critical.Count -gt 0) { exit 2 } elseif ($flagged.Count -gt 0) { exit 1 } else { exit 0 }