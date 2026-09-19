[CmdletBinding()]
param(
    [ValidateRange(1,3650)]
    [int]$WarningDays = 30,

    [ValidateSet('My','CA','Root','WebHosting','Remote Desktop')]
    [string[]]$StoreName = @('My','WebHosting'),

    [string]$ComputerName = $env:COMPUTERNAME,

    [switch]$IncludeExpired,

    [switch]$IncludeWithoutPrivateKey,

    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath ("certificate-expiry-{0}-{1}.csv" -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host ("[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message)
}

function Get-CertificateStatus {
    param(
        [Parameter(Mandatory)][datetime]$NotAfter,
        [Parameter(Mandatory)][int]$ThresholdDays
    )

    $remaining = [math]::Floor(($NotAfter.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalDays)
    if ($remaining -lt 0) { return 'Expired' }
    if ($remaining -le $ThresholdDays) { return 'ExpiringSoon' }
    return 'Healthy'
}

try {
    $now = Get-Date
    $threshold = $now.AddDays($WarningDays)
    $results = [System.Collections.Generic.List[object]]::new()

    Write-Log INFO "Auditing certificate stores on '$ComputerName'; warning threshold: $WarningDays day(s)."

    foreach ($store in $StoreName) {
        $path = "Cert:\LocalMachine\$store"
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log WARN "Certificate store '$path' does not exist; skipping."
            continue
        }

        $certificates = Get-ChildItem -LiteralPath $path -ErrorAction Stop
        foreach ($cert in $certificates) {
            if (-not $IncludeWithoutPrivateKey -and -not $cert.HasPrivateKey -and $store -in @('My','WebHosting')) {
                continue
            }

            $isExpired = $cert.NotAfter -lt $now
            $isExpiring = $cert.NotAfter -le $threshold
            if (-not $isExpiring) { continue }
            if ($isExpired -and -not $IncludeExpired) { continue }

            $daysRemaining = [math]::Floor(($cert.NotAfter.ToUniversalTime() - $now.ToUniversalTime()).TotalDays)
            $eku = @($cert.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName }) -join '; '

            $results.Add([pscustomobject]@{
                ComputerName       = $ComputerName
                Store              = $store
                Status             = Get-CertificateStatus -NotAfter $cert.NotAfter -ThresholdDays $WarningDays
                DaysRemaining      = $daysRemaining
                Subject            = $cert.Subject
                Issuer             = $cert.Issuer
                Thumbprint         = $cert.Thumbprint
                SerialNumber       = $cert.SerialNumber
                NotBefore          = $cert.NotBefore.ToString('o')
                NotAfter           = $cert.NotAfter.ToString('o')
                HasPrivateKey      = $cert.HasPrivateKey
                SignatureAlgorithm = $cert.SignatureAlgorithm.FriendlyName
                EnhancedKeyUsage   = $eku
                FriendlyName       = $cert.FriendlyName
            })
        }
    }

    $ordered = @($results | Sort-Object @{Expression='Status';Descending=$false}, @{Expression='DaysRemaining';Descending=$false}, Store, Subject)

    if ($ordered.Count -eq 0) {
        Write-Log INFO 'No certificates matched the selected expiration criteria.'
    }
    else {
        Write-Log WARN ("Found {0} certificate(s) matching the selected expiration criteria." -f $ordered.Count)
        $ordered | Format-Table Status,DaysRemaining,Store,Subject,NotAfter,Thumbprint -AutoSize
    }

    if (-not $NoExport) {
        $directory = Split-Path -Parent $OutputPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $ordered | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log INFO "CSV report written to '$OutputPath'."
    }

    $ordered
}
catch {
    Write-Log ERROR $_.Exception.Message
    throw
}
