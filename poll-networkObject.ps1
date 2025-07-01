# network object poller
# v0.1
# Kevin Dutkiewicz
# 2025-06-28
#
# Basic workflow:
# 1) define target
# 2) define port
# 3) update final output variable with combined statuses

# Create hashtable for output
# ############
# Ping:Healthy
# HTTPCode:Healthy
# Pattern:FAILED - (error)
# ############

param(
    [string]$target, 
    [Parameter(Mandatory=$false)][int]$port,
    [Parameter(Mandatory=$false)][string]$testPattern
    )

# add more if needed
$httpPorts = @(80,443)

write-host "Target: " $target
write-host "Port: " $port
write-host "Test Pattern: " $testPattern

$resultsTable = @{
    ping = "Untested"
    httpcode = "Untested"
    pattern = "Untested"
}

function pingTest ([string]$pingTarget,[int]$pingPort) {
    if ($pingTarget -match "^(.*?)\/") {
        $finalPingTarget = $($matches[1])
    } else {
        $finalPingTarget = $pingTarget
    }
    #write-host "I have target " $finalPingTarget
    #write-host "I have port " $pingPort
    if ($port -ne 0) {
        $pingResult = Test-NetConnection -ComputerName $finalPingTarget -InformationLevel Detailed -Port $pingPort
        if ($pingResult.TcpTestSucceeded -eq $true) {
            write-host "Port Test Succeeded"
            $resultsTable["ping"] = "Port Test: " + $pingport + " OK"
        } else {
            write-host "Port Test Failed"
            $resultsTable["ping"] = "Port Test: " + $pingport + " FAILED"
        }
    } else {
        $pingResult = Test-NetConnection -ComputerName $finalPingTarget.Trim() -InformationLevel Detailed
        if ($pingResult.PingSucceeded -eq $true) {
            write-host "Ping Succeeded"
            $resultsTable["ping"] = "Ping Test: OK"

        } else {
            write-host "Ping Failed"
            $resultsTable["ping"] = "Ping Test: FAILED"
        }
    }
}

function httpCode([string]$httpCodeTarget,[int]$httpCodePort){
    try {
        $response = Invoke-WebRequest -Uri $httpCodeTarget -Method Get
        $statusCode = $response.StatusCode
        write-host "HTTP Status Code: $statusCode"
        if ($statusCode -match "2\d{2}") {
            write-host "Found 200 series HTTP Code"
            $resultsTable["httpcode"] = "HTTPCode: " + $statusCode + " OK"
        } else {
            write-host "Did not find 200 series HTTP Code"
            $resultsTable["httpcode"] = "HTTPCode: " + $statusCode + " FAILED"
        }
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
        write-host "Caught error with status code: $($response.StatusCode.Value__)"
        $resultsTable["httpcode"] = "HTTPCode: " + $($response.StatusCode.Value__) + " FAILED"
    }
}

function patternTest([string]$patternTestTarget,[int]$patternTestPort,[string]$patternTestPattern) {
    try {
        $response = Invoke-WebRequest -Uri $patternTestTarget
        if ($response.Content -match $patternTestPattern) {
            write-host "Pattern found: $($matches[0])"
            $resultsTable["pattern"] = "Pattern Test: OK"
        } else {
            write-host "Pattern not found."
            $resultsTable["pattern"] = "Pattern Test: FAILED"
        }
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        write-host "Caught error with status code: $($response.StatusCode.Value__)"
        $resultsTable["pattern"] = "Pattern Test: FAILED"
    }
}

# Kick off the basic ping test
pingTest $target $port

# Kick off the HTTP code test
if ($httpPorts -contains $port) {
    write-host "HTTP code test"
    httpCode $target $port
}

# Kick off the pattern test if there is a pattern
if ($testPattern) {
    write-host "Pattern test"
    patternTest $target $port $testPattern
}

write-host "--------"
write-host "Final Result: "
write-host $resultsTable.ping
write-host $resultsTable.httpcode
write-host $resultsTable.pattern
