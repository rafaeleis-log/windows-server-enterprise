<#
.SYNOPSIS
Enterprise GPO Backup Script

.DESCRIPTION
Realiza backup completo das GPOs, cria pasta por data, registra logs,
gera relatório CSV e remove backups antigos.

.AUTHOR
Rafael Ferreira Eis
#>

param(
[string]$BackupRoot="C:\Backup\GPO",
[int]$RetentionDays=30
)

Import-Module GroupPolicy

$Date=Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BackupPath=Join-Path $BackupRoot $Date
$Log=Join-Path $BackupRoot "BackupGPO_$Date.log"

function Log($m){
$line="$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"
$line|Out-File -Append $Log
Write-Host $line
}

New-Item -ItemType Directory -Force -Path $BackupPath|Out-Null
Log "Iniciando backup das GPOs"

$Report=@()

Get-GPO -All | ForEach-Object{
    try{
        Backup-GPO -Guid $_.Id -Path $BackupPath -ErrorAction Stop
        $Report+=[pscustomobject]@{
            GPO=$_.DisplayName
            Status="Success"
            Backup=$BackupPath
        }
        Log "Backup realizado: $($_.DisplayName)"
    }
    catch{
        $Report+=[pscustomobject]@{
            GPO=$_.DisplayName
            Status="Failed"
            Backup=""
        }
        Log "Erro: $($_.DisplayName)"
    }
}

$Csv=Join-Path $BackupPath "BackupReport.csv"
$Report|Export-Csv $Csv -NoTypeInformation -Encoding UTF8

Get-ChildItem $BackupRoot -Directory |
Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays)} |
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Log "Backup concluído."
