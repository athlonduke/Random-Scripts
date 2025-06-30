# network object poller
# v0.1
# Kevin Dutkiewicz
# 2025-06-28
#
# Basic workflow:
# 1) define target
# 2) define port
# 3) update final output variable with combined statuses

# use binary string to declare results
# 0 - ping. use weighed, 8 out of 10 for return 1
# 1 - httpcode. anything 2XX is ok and will return 1
# 2 - content validation. look for a text result and verify existance
# example 111 - all good
# example 000 - all failed
# example 110 - ping, http code pass, but page does not contain expected output

param(
    [string]$target, 
    [Parameter(Mandatory=$false)][int]$port,
    [Parameter(Mandatory=$false)][string]$testPattern
    )

# add more if needed
$httpPorts = @(80,443)

Write-Host "Target: " $target
Write-Host "Port: " $port
Write-Host "Test Pattern: " $testPattern

$finalResult = 0 # pessimistic approach: start fail and build up

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
            Write-Host "Port Test Succeeded"
            return(1)
        } else {
            Write-Host "Port Test Failed"
            return(0)

        }
    } else {
        $pingResult = Test-NetConnection -ComputerName $finalPingTarget.Trim() -InformationLevel Detailed
        if ($pingResult.PingSucceeded -eq $true) {
            Write-Host "Ping Succeeded"
            return(1)

        } else {
            Write-Host "Ping Failed"
            return(0)

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
            return (1)
        } else {
            write-host "Did not find 200 series HTTP Code"
            return (0)
        }
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        Write-Host "Caught error with status code: $($response.StatusCode.Value__)"
        return (0)
    }
}

function patternTest([string]$patternTestTarget,[int]$patternTestPort,[string]$patternTestPattern) {
    try {
        $response = Invoke-WebRequest -Uri $patternTestTarget
        if ($response.Content -match $patternTestPattern) {
            Write-Host "Pattern found: $($matches[0])"
            return (1)
        } else {
            Write-Host "Pattern not found."
            return (0)
        }
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        Write-Host "Caught error with status code: $($response.StatusCode.Value__)"
        return (0)
    }
}

# Kick off the basic ping test
$finalResult = pingTest $target $port

# Kick off the HTTP code test
if ($httpPorts -contains $port) {
    write-host "HTTP code test"
    $finalResult = httpCode $target $port
}

# Kick off the pattern test if there is a pattern
if ($testPattern) {
    Write-Host "Pattern test"
    $finalResult = patternTest $target $port $testPattern
}

Write-Host "Final Result: "$finalResult