<#
.SYNOPSIS
    Inventário corporativo de Windows Server com geração de relatórios.

.DESCRIPTION
    Script demonstrativo para portfólio profissional.
    Coleta informações de sistema operacional, hardware, discos, rede,
    serviços críticos, hotfixes, eventos e dados básicos do domínio.

.AUTHOR
    Rafael Ferreira Eis

.PROJECT
    Windows Server Enterprise

.VERSION
    1.0

.REQUIREMENTS
    - PowerShell 5.1 ou superior
    - Permissão de leitura local no servidor
    - Execução como Administrador recomendada

.EXAMPLE
    .\Inventory.ps1

.EXAMPLE
    .\Inventory.ps1 -OutputPath ".\reports" -IncludeEvents
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeEvents,

    [Parameter(Mandatory = $false)]
    [int]$EventHours = 24
)

$Date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ComputerName = $env:COMPUTERNAME

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "Inventory_$ComputerName_$Date.log"
$CsvFile = Join-Path $OutputPath "Inventory_$ComputerName_$Date.csv"
$HtmlFile = Join-Path $OutputPath "Inventory_$ComputerName_$Date.html"

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

function Get-SafeCimInstance {
    param(
        [string]$ClassName,
        [string]$Namespace = "root\cimv2"
    )

    try {
        return Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop
    }
    catch {
        Write-Log "Falha ao consultar CIM Class $ClassName. $_" "ERROR"
        return $null
    }
}

function Convert-BytesToGB {
    param([double]$Bytes)

    if ($null -eq $Bytes -or $Bytes -eq 0) {
        return 0
    }

    return [math]::Round($Bytes / 1GB, 2)
}

function Get-Uptime {
    param([datetime]$LastBoot)

    $Uptime = (Get-Date) - $LastBoot
    return "{0} dias, {1} horas, {2} minutos" -f $Uptime.Days, $Uptime.Hours, $Uptime.Minutes
}

function Get-OperatingSystemInfo {
    Write-Log "Coletando informações do sistema operacional."

    $OS = Get-SafeCimInstance -ClassName "Win32_OperatingSystem"
    $Computer = Get-SafeCimInstance -ClassName "Win32_ComputerSystem"

    if ($null -eq $OS) {
        return $null
    }

    return [PSCustomObject]@{
        ComputerName = $ComputerName
        Domain = $Computer.Domain
        OperatingSystem = $OS.Caption
        Version = $OS.Version
        BuildNumber = $OS.BuildNumber
        Architecture = $OS.OSArchitecture
        InstallDate = $OS.InstallDate
        LastBootUpTime = $OS.LastBootUpTime
        Uptime = Get-Uptime -LastBoot $OS.LastBootUpTime
    }
}

function Get-HardwareInfo {
    Write-Log "Coletando informações de hardware."

    $Computer = Get-SafeCimInstance -ClassName "Win32_ComputerSystem"
    $Bios = Get-SafeCimInstance -ClassName "Win32_BIOS"
    $Processor = Get-SafeCimInstance -ClassName "Win32_Processor"

    return [PSCustomObject]@{
        Manufacturer = $Computer.Manufacturer
        Model = $Computer.Model
        SerialNumber = $Bios.SerialNumber
        BIOSVersion = ($Bios.SMBIOSBIOSVersion -join ", ")
        Processor = ($Processor.Name -join ", ")
        CPUCores = ($Processor.NumberOfCores | Measure-Object -Sum).Sum
        LogicalProcessors = ($Processor.NumberOfLogicalProcessors | Measure-Object -Sum).Sum
        TotalMemoryGB = Convert-BytesToGB -Bytes $Computer.TotalPhysicalMemory
    }
}

function Get-DiskInfo {
    Write-Log "Coletando informações de disco."

    $Disks = Get-SafeCimInstance -ClassName "Win32_LogicalDisk" |
        Where-Object { $_.DriveType -eq 3 }

    $DiskList = @()

    foreach ($Disk in $Disks) {
        $SizeGB = Convert-BytesToGB -Bytes $Disk.Size
        $FreeGB = Convert-BytesToGB -Bytes $Disk.FreeSpace
        $UsedGB = [math]::Round($SizeGB - $FreeGB, 2)

        if ($SizeGB -gt 0) {
            $UsedPercent = [math]::Round(($UsedGB / $SizeGB) * 100, 2)
        }
        else {
            $UsedPercent = 0
        }

        $DiskList += [PSCustomObject]@{
            Drive = $Disk.DeviceID
            FileSystem = $Disk.FileSystem
            SizeGB = $SizeGB
            UsedGB = $UsedGB
            FreeGB = $FreeGB
            UsedPercent = $UsedPercent
        }
    }

    return $DiskList
}

function Get-NetworkInfo {
    Write-Log "Coletando informações de rede."

    $Adapters = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $_.IPEnabled -eq $true }

    $NetworkList = @()

    foreach ($Adapter in $Adapters) {
        $IPv4 = ($Adapter.IPAddress | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" }) -join ", "
        $Subnet = ($Adapter.IPSubnet | Select-Object -First 1)
        $Gateway = ($Adapter.DefaultIPGateway -join ", ")
        $DNS = ($Adapter.DNSServerSearchOrder -join ", ")

        $NetworkList += [PSCustomObject]@{
            Description = $Adapter.Description
            MACAddress = $Adapter.MACAddress
            IPv4 = $IPv4
            Subnet = $Subnet
            Gateway = $Gateway
            DNS = $DNS
            DHCPEnabled = $Adapter.DHCPEnabled
        }
    }

    return $NetworkList
}

function Get-CriticalServices {
    Write-Log "Verificando serviços críticos."

    $CriticalServices = @(
        "NTDS",
        "DNS",
        "DHCPServer",
        "Netlogon",
        "DFSR",
        "LanmanServer",
        "W32Time",
        "WinRM"
    )

    $ServiceList = @()

    foreach ($ServiceName in $CriticalServices) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($null -eq $Service) {
            $ServiceList += [PSCustomObject]@{
                Name = $ServiceName
                DisplayName = "Not Found"
                Status = "Not Found"
                StartType = "N/A"
            }
        }
        else {
            $ServiceList += [PSCustomObject]@{
                Name = $Service.Name
                DisplayName = $Service.DisplayName
                Status = $Service.Status
                StartType = $Service.StartType
            }
        }
    }

    return $ServiceList
}

function Get-HotfixInfo {
    Write-Log "Coletando últimos hotfixes."

    try {
        return Get-HotFix |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 10 HotFixID, Description, InstalledBy, InstalledOn
    }
    catch {
        Write-Log "Falha ao coletar hotfixes. $_" "ERROR"
        return @()
    }
}

function Get-DomainInfo {
    Write-Log "Coletando informações básicas de domínio."

    $Computer = Get-SafeCimInstance -ClassName "Win32_ComputerSystem"

    $DomainRole = switch ($Computer.DomainRole) {
        0 { "Standalone Workstation" }
        1 { "Member Workstation" }
        2 { "Standalone Server" }
        3 { "Member Server" }
        4 { "Backup Domain Controller" }
        5 { "Primary Domain Controller" }
        default { "Unknown" }
    }

    return [PSCustomObject]@{
        Domain = $Computer.Domain
        PartOfDomain = $Computer.PartOfDomain
        DomainRole = $DomainRole
    }
}

function Get-RecentCriticalEvents {
    param([int]$Hours)

    Write-Log "Coletando eventos críticos das últimas $Hours horas."

    $StartTime = (Get-Date).AddHours(-$Hours)

    try {
        return Get-WinEvent -FilterHashtable @{
            LogName = "System"
            Level = 1,2
            StartTime = $StartTime
        } -ErrorAction Stop |
        Select-Object -First 20 TimeCreated, ProviderName, Id, LevelDisplayName, Message
    }
    catch {
        Write-Log "Falha ao coletar eventos críticos. $_" "WARNING"
        return @()
    }
}

function New-HtmlSection {
    param(
        [string]$Title,
        [object]$Data
    )

    if ($null -eq $Data) {
        return "<h2>$Title</h2><p>Nenhum dado coletado.</p>"
    }

    return "<h2>$Title</h2>" + ($Data | ConvertTo-Html -Fragment)
}

function New-InventoryHtmlReport {
    param(
        [object]$OSInfo,
        [object]$HardwareInfo,
        [object]$DomainInfo,
        [object]$DiskInfo,
        [object]$NetworkInfo,
        [object]$ServiceInfo,
        [object]$HotfixInfo,
        [object]$EventInfo
    )

    Write-Log "Gerando relatório HTML."

    $Style = @"
<style>
body { font-family: Arial, sans-serif; background-color: #f5f7fa; color: #222; margin: 30px; }
h1 { color: #1f4e79; }
h2 { color: #2f5597; border-bottom: 1px solid #ccc; padding-bottom: 5px; }
table { border-collapse: collapse; width: 100%; margin-bottom: 25px; background-color: #fff; }
th { background-color: #1f4e79; color: white; padding: 8px; }
td { border: 1px solid #ddd; padding: 8px; }
tr:nth-child(even) { background-color: #f2f2f2; }
.footer { margin-top: 30px; font-size: 12px; color: #666; }
</style>
"@

    $Html = @"
<html>
<head>
<title>Windows Server Inventory - $ComputerName</title>
$Style
</head>
<body>
<h1>Windows Server Inventory</h1>
<p><strong>Servidor:</strong> $ComputerName</p>
<p><strong>Data:</strong> $(Get-Date)</p>
"@

    $Html += New-HtmlSection -Title "Sistema Operacional" -Data $OSInfo
    $Html += New-HtmlSection -Title "Hardware" -Data $HardwareInfo
    $Html += New-HtmlSection -Title "Domínio" -Data $DomainInfo
    $Html += New-HtmlSection -Title "Discos" -Data $DiskInfo
    $Html += New-HtmlSection -Title "Rede" -Data $NetworkInfo
    $Html += New-HtmlSection -Title "Serviços Críticos" -Data $ServiceInfo
    $Html += New-HtmlSection -Title "Últimos Hotfixes" -Data $HotfixInfo

    if ($IncludeEvents) {
        $Html += New-HtmlSection -Title "Eventos Críticos Recentes" -Data $EventInfo
    }

    $Html += @"
<div class="footer">
Relatório gerado por Inventory.ps1 - Windows Server Enterprise - Rafael Ferreira Eis
</div>
</body>
</html>
"@

    $Html | Out-File -FilePath $HtmlFile -Encoding UTF8
}

Write-Log "Iniciando inventário do servidor $ComputerName."

$OSInfo = Get-OperatingSystemInfo
$HardwareInfo = Get-HardwareInfo
$DomainInfo = Get-DomainInfo
$DiskInfo = Get-DiskInfo
$NetworkInfo = Get-NetworkInfo
$ServiceInfo = Get-CriticalServices
$HotfixInfo = Get-HotfixInfo

$EventInfo = @()
if ($IncludeEvents) {
    $EventInfo = Get-RecentCriticalEvents -Hours $EventHours
}

$CsvObject = [PSCustomObject]@{
    ComputerName = $OSInfo.ComputerName
    Domain = $OSInfo.Domain
    OperatingSystem = $OSInfo.OperatingSystem
    Version = $OSInfo.Version
    BuildNumber = $OSInfo.BuildNumber
    Uptime = $OSInfo.Uptime
    Manufacturer = $HardwareInfo.Manufacturer
    Model = $HardwareInfo.Model
    SerialNumber = $HardwareInfo.SerialNumber
    Processor = $HardwareInfo.Processor
    CPUCores = $HardwareInfo.CPUCores
    LogicalProcessors = $HardwareInfo.LogicalProcessors
    TotalMemoryGB = $HardwareInfo.TotalMemoryGB
    DiskCount = ($DiskInfo | Measure-Object).Count
    NetworkAdapters = ($NetworkInfo | Measure-Object).Count
}

try {
    $CsvObject | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
    Write-Log "Relatório CSV gerado: $CsvFile" "SUCCESS"
}
catch {
    Write-Log "Erro ao gerar CSV. $_" "ERROR"
}

try {
    New-InventoryHtmlReport `
        -OSInfo $OSInfo `
        -HardwareInfo $HardwareInfo `
        -DomainInfo $DomainInfo `
        -DiskInfo $DiskInfo `
        -NetworkInfo $NetworkInfo `
        -ServiceInfo $ServiceInfo `
        -HotfixInfo $HotfixInfo `
        -EventInfo $EventInfo

    Write-Log "Relatório HTML gerado: $HtmlFile" "SUCCESS"
}
catch {
    Write-Log "Erro ao gerar relatório HTML. $_" "ERROR"
}

Write-Log "Inventário finalizado com sucesso." "SUCCESS"
