<#
.SYNOPSIS
    Monitoramento corporativo de serviços críticos em Windows Server.

.DESCRIPTION
    Script demonstrativo para portfólio profissional.
    Verifica serviços críticos, status, tipo de inicialização, dependências,
    executa tentativa de reinício opcional e gera logs, CSV e HTML.

.AUTHOR
    Rafael Ferreira Eis

.PROJECT
    Windows Server Enterprise

.VERSION
    1.0

.REQUIREMENTS
    - PowerShell 5.1 ou superior
    - Execução como Administrador recomendada
    - Permissão para consultar e reiniciar serviços

.EXAMPLE
    .\Check-Services.ps1

.EXAMPLE
    .\Check-Services.ps1 -AutoRestart

.EXAMPLE
    .\Check-Services.ps1 -Services "DNS","Netlogon","DFSR"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Services = @(
        "NTDS",
        "DNS",
        "DHCPServer",
        "Netlogon",
        "DFSR",
        "LanmanServer",
        "W32Time",
        "WinRM",
        "EventLog",
        "Spooler"
    ),

    [Parameter(Mandatory = $false)]
    [switch]$AutoRestart,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs"
)

$Date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ComputerName = $env:COMPUTERNAME

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "Check-Services_$ComputerName_$Date.log"
$CsvFile = Join-Path $OutputPath "Check-Services_$ComputerName_$Date.csv"
$HtmlFile = Join-Path $OutputPath "Check-Services_$ComputerName_$Date.html"

$Results = @()

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $Line

    switch ($Level) {
        "INFO"    { Write-Host $Line -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $Line -ForegroundColor Green }
        "WARNING" { Write-Host $Line -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Line -ForegroundColor Red }
        default   { Write-Host $Line }
    }
}

function Get-ServiceStartType {
    param([string]$ServiceName)

    try {
        $CimService = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        return $CimService.StartMode
    }
    catch {
        return "Unknown"
    }
}

function Get-ServiceDependenciesSafe {
    param([string]$ServiceName)

    try {
        $Service = Get-Service -Name $ServiceName -ErrorAction Stop
        $Dependencies = $Service.ServicesDependedOn | Select-Object -ExpandProperty Name
        if ($Dependencies) {
            return ($Dependencies -join ", ")
        }
        return "None"
    }
    catch {
        return "Unknown"
    }
}

function Restart-ServiceSafe {
    param([string]$ServiceName)

    try {
        Write-Log "Tentando reiniciar serviço: $ServiceName" "WARNING"
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        Start-Sleep -Seconds 5

        $Service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($Service.Status -eq "Running") {
            Write-Log "Serviço reiniciado com sucesso: $ServiceName" "SUCCESS"
            return "Restarted"
        }
        else {
            Write-Log "Serviço não voltou para Running: $ServiceName" "ERROR"
            return "Restart Failed"
        }
    }
    catch {
        Write-Log "Erro ao reiniciar serviço $ServiceName. $_" "ERROR"
        return "Restart Error"
    }
}

function Test-ServiceHealth {
    param([string]$ServiceName)

    Write-Log "Verificando serviço: $ServiceName"

    $Action = "None"
    $Health = "Unknown"
    $Status = "Not Found"
    $DisplayName = "Not Found"
    $StartType = "Unknown"
    $Dependencies = "Unknown"

    try {
        $Service = Get-Service -Name $ServiceName -ErrorAction Stop

        $Status = $Service.Status.ToString()
        $DisplayName = $Service.DisplayName
        $StartType = Get-ServiceStartType -ServiceName $ServiceName
        $Dependencies = Get-ServiceDependenciesSafe -ServiceName $ServiceName

        if ($Service.Status -eq "Running") {
            $Health = "Healthy"
            Write-Log "Serviço OK: $ServiceName" "SUCCESS"
        }
        else {
            $Health = "Unhealthy"
            Write-Log "Serviço fora de execução: $ServiceName | Status: $Status" "WARNING"

            if ($AutoRestart) {
                $Action = Restart-ServiceSafe -ServiceName $ServiceName

                $ServiceAfterRestart = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($ServiceAfterRestart -and $ServiceAfterRestart.Status -eq "Running") {
                    $Health = "Recovered"
                    $Status = "Running"
                }
            }
        }
    }
    catch {
        $Health = "Not Found"
        $Action = "No Action"
        Write-Log "Serviço não encontrado: $ServiceName" "ERROR"
    }

    return [PSCustomObject]@{
        ComputerName = $ComputerName
        ServiceName = $ServiceName
        DisplayName = $DisplayName
        Status = $Status
        StartType = $StartType
        Dependencies = $Dependencies
        Health = $Health
        Action = $Action
        CheckedAt = Get-Date
    }
}

function New-HtmlReport {
    param([array]$Data)

    Write-Log "Gerando relatório HTML."

    $Healthy = ($Data | Where-Object { $_.Health -eq "Healthy" }).Count
    $Recovered = ($Data | Where-Object { $_.Health -eq "Recovered" }).Count
    $Unhealthy = ($Data | Where-Object { $_.Health -eq "Unhealthy" }).Count
    $NotFound = ($Data | Where-Object { $_.Health -eq "Not Found" }).Count

    $Style = @"
<style>
body {
    font-family: Arial, sans-serif;
    background-color: #f5f7fa;
    color: #222;
    margin: 30px;
}
h1 {
    color: #1f4e79;
}
h2 {
    color: #2f5597;
}
.summary {
    display: flex;
    gap: 15px;
    margin-bottom: 25px;
}
.card {
    background: #fff;
    padding: 15px;
    border-radius: 8px;
    border: 1px solid #ddd;
    min-width: 140px;
}
table {
    border-collapse: collapse;
    width: 100%;
    background-color: #fff;
}
th {
    background-color: #1f4e79;
    color: white;
    padding: 8px;
}
td {
    border: 1px solid #ddd;
    padding: 8px;
}
tr:nth-child(even) {
    background-color: #f2f2f2;
}
.footer {
    margin-top: 30px;
    font-size: 12px;
    color: #666;
}
</style>
"@

    $Html = @"
<html>
<head>
<title>Windows Server Services Report - $ComputerName</title>
$Style
</head>
<body>
<h1>Windows Server Services Report</h1>
<p><strong>Servidor:</strong> $ComputerName</p>
<p><strong>Data:</strong> $(Get-Date)</p>

<div class="summary">
    <div class="card"><strong>Healthy</strong><br>$Healthy</div>
    <div class="card"><strong>Recovered</strong><br>$Recovered</div>
    <div class="card"><strong>Unhealthy</strong><br>$Unhealthy</div>
    <div class="card"><strong>Not Found</strong><br>$NotFound</div>
</div>

<h2>Detalhes dos Serviços</h2>
"@

    $Html += ($Data | ConvertTo-Html -Fragment)

    $Html += @"
<div class="footer">
Relatório gerado por Check-Services.ps1 - Windows Server Enterprise - Rafael Ferreira Eis
</div>
</body>
</html>
"@

    $Html | Out-File -FilePath $HtmlFile -Encoding UTF8
}

Write-Log "Iniciando verificação de serviços no servidor $ComputerName."

foreach ($ServiceName in $Services) {
    $Results += Test-ServiceHealth -ServiceName $ServiceName
}

try {
    $Results | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
    Write-Log "Relatório CSV gerado: $CsvFile" "SUCCESS"
}
catch {
    Write-Log "Erro ao gerar CSV. $_" "ERROR"
}

try {
    New-HtmlReport -Data $Results
    Write-Log "Relatório HTML gerado: $HtmlFile" "SUCCESS"
}
catch {
    Write-Log "Erro ao gerar HTML. $_" "ERROR"
}

$HealthyCount = ($Results | Where-Object { $_.Health -eq "Healthy" }).Count
$RecoveredCount = ($Results | Where-Object { $_.Health -eq "Recovered" }).Count
$UnhealthyCount = ($Results | Where-Object { $_.Health -eq "Unhealthy" }).Count
$NotFoundCount = ($Results | Where-Object { $_.Health -eq "Not Found" }).Count

Write-Log "Resumo da execução:"
Write-Log "Healthy: $HealthyCount"
Write-Log "Recovered: $RecoveredCount"
Write-Log "Unhealthy: $UnhealthyCount"
Write-Log "Not Found: $NotFoundCount"
Write-Log "Verificação finalizada." "SUCCESS"
