<#
.SYNOPSIS
    Criação corporativa de usuários no Active Directory a partir de arquivo CSV.

.DESCRIPTION
    Script demonstrativo para portfólio profissional.
    Realiza validações, cria usuários, define senha temporária, força troca no primeiro logon,
    adiciona grupos, cria pasta home opcional e gera logs/relatórios.

.AUTHOR
    Rafael Ferreira Eis

.PROJECT
    Windows Server Enterprise

.VERSION
    1.0

.REQUIREMENTS
    - PowerShell executado como Administrador
    - RSAT / ActiveDirectory Module
    - Permissão para criar usuários no Active Directory

.EXAMPLE
    .\Create-AD-Users.ps1 -CsvPath ".\users.csv" -Domain "empresa.local" -DefaultOU "OU=Usuarios,DC=empresa,DC=local"

.CSV EXAMPLE
    FirstName,LastName,Login,Department,Title,Groups
    Joao,Silva,joao.silva,TI,Analista de Suporte,"TI-Users;VPN-Users"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath = ".\users.csv",

    [Parameter(Mandatory = $false)]
    [string]$Domain = "empresa.local",

    [Parameter(Mandatory = $false)]
    [string]$DefaultOU = "OU=Usuarios,DC=empresa,DC=local",

    [Parameter(Mandatory = $false)]
    [string]$TemporaryPassword = "Temp@12345",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\reports",

    [Parameter(Mandatory = $false)]
    [switch]$CreateHomeFolder,

    [Parameter(Mandatory = $false)]
    [string]$HomeFolderRoot = "\\fileserver\home"
)

# ==============================
# Preparação
# ==============================

$Date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

if (!(Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "Create-AD-Users_$Date.log"
$ReportFile = Join-Path $ReportPath "Create-AD-Users_Report_$Date.csv"

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

function Test-RequiredModule {
    param([string]$ModuleName)

    if (!(Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Log "Módulo não encontrado: $ModuleName" "ERROR"
        throw "Módulo $ModuleName não está instalado."
    }

    Import-Module $ModuleName -ErrorAction Stop
    Write-Log "Módulo carregado: $ModuleName" "SUCCESS"
}

function Test-CsvColumns {
    param([array]$Users)

    $RequiredColumns = @("FirstName", "LastName", "Login")
    $CsvColumns = $Users[0].PSObject.Properties.Name

    foreach ($Column in $RequiredColumns) {
        if ($Column -notin $CsvColumns) {
            Write-Log "Coluna obrigatória ausente no CSV: $Column" "ERROR"
            throw "CSV inválido. Coluna obrigatória ausente: $Column"
        }
    }

    Write-Log "Validação de colunas do CSV concluída." "SUCCESS"
}

function New-SafePassword {
    param([string]$Password)

    return ConvertTo-SecureString $Password -AsPlainText -Force
}

function Test-ADUserExists {
    param([string]$Login)

    $ExistingUser = Get-ADUser -Filter "SamAccountName -eq '$Login'" -ErrorAction SilentlyContinue

    if ($ExistingUser) {
        return $true
    }

    return $false
}

function Test-ADGroupExists {
    param([string]$GroupName)

    $Group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue

    if ($Group) {
        return $true
    }

    return $false
}

function Add-UserToGroups {
    param(
        [string]$Login,
        [string]$Groups
    )

    if ([string]::IsNullOrWhiteSpace($Groups)) {
        Write-Log "Nenhum grupo informado para o usuário: $Login" "WARNING"
        return
    }

    $GroupList = $Groups -split ";"

    foreach ($Group in $GroupList) {
        $GroupName = $Group.Trim()

        if ([string]::IsNullOrWhiteSpace($GroupName)) {
            continue
        }

        if (Test-ADGroupExists -GroupName $GroupName) {
            try {
                Add-ADGroupMember -Identity $GroupName -Members $Login -ErrorAction Stop
                Write-Log "Usuário $Login adicionado ao grupo $GroupName" "SUCCESS"
            }
            catch {
                Write-Log "Erro ao adicionar $Login ao grupo $GroupName. $_" "ERROR"
            }
        }
        else {
            Write-Log "Grupo não encontrado: $GroupName" "WARNING"
        }
    }
}

function New-HomeFolder {
    param([string]$Login)

    $UserHome = Join-Path $HomeFolderRoot $Login

    try {
        if (!(Test-Path $UserHome)) {
            New-Item -ItemType Directory -Path $UserHome -Force | Out-Null
            Write-Log "Pasta home criada: $UserHome" "SUCCESS"
        }
        else {
            Write-Log "Pasta home já existe: $UserHome" "WARNING"
        }
    }
    catch {
        Write-Log "Erro ao criar pasta home para $Login. $_" "ERROR"
    }
}

# ==============================
# Execução
# ==============================

Write-Log "Iniciando criação de usuários no Active Directory."
Write-Log "Arquivo CSV: $CsvPath"
Write-Log "Domínio: $Domain"
Write-Log "OU padrão: $DefaultOU"

try {
    Test-RequiredModule -ModuleName "ActiveDirectory"
}
catch {
    Write-Log "Falha ao carregar módulo ActiveDirectory. Encerrando execução." "ERROR"
    exit 1
}

if (!(Test-Path $CsvPath)) {
    Write-Log "Arquivo CSV não encontrado: $CsvPath" "ERROR"
    exit 1
}

try {
    $Users = Import-Csv $CsvPath
}
catch {
    Write-Log "Erro ao importar CSV. $_" "ERROR"
    exit 1
}

if ($Users.Count -eq 0) {
    Write-Log "CSV vazio. Nenhum usuário para processar." "ERROR"
    exit 1
}

try {
    Test-CsvColumns -Users $Users
}
catch {
    Write-Log "Falha na validação do CSV. Encerrando execução." "ERROR"
    exit 1
}

foreach ($User in $Users) {

    $FirstName = $User.FirstName.Trim()
    $LastName  = $User.LastName.Trim()
    $Login     = $User.Login.Trim().ToLower()
    $FullName  = "$FirstName $LastName"
    $UPN       = "$Login@$Domain"

    $Department = $User.Department
    $Title      = $User.Title
    $Groups     = $User.Groups

    $Status = "Pending"
    $Message = ""

    Write-Log "Processando usuário: $Login"

    if ([string]::IsNullOrWhiteSpace($FirstName) -or
        [string]::IsNullOrWhiteSpace($LastName) -or
        [string]::IsNullOrWhiteSpace($Login)) {

        $Status = "Failed"
        $Message = "Campos obrigatórios vazios."

        Write-Log "Usuário ignorado por campos obrigatórios vazios." "ERROR"

        $Results += [PSCustomObject]@{
            Login = $Login
            Name = $FullName
            Status = $Status
            Message = $Message
        }

        continue
    }

    if (Test-ADUserExists -Login $Login) {
        $Status = "Skipped"
        $Message = "Usuário já existe."

        Write-Log "Usuário já existe: $Login" "WARNING"

        $Results += [PSCustomObject]@{
            Login = $Login
            Name = $FullName
            Status = $Status
            Message = $Message
        }

        continue
    }

    try {
        New-ADUser `
            -Name $FullName `
            -GivenName $FirstName `
            -Surname $LastName `
            -DisplayName $FullName `
            -SamAccountName $Login `
            -UserPrincipalName $UPN `
            -Path $DefaultOU `
            -Department $Department `
            -Title $Title `
            -Enabled $true `
            -ChangePasswordAtLogon $true `
            -AccountPassword (New-SafePassword -Password $TemporaryPassword) `
            -ErrorAction Stop

        Write-Log "Usuário criado com sucesso: $Login" "SUCCESS"

        Add-UserToGroups -Login $Login -Groups $Groups

        if ($CreateHomeFolder) {
            New-HomeFolder -Login $Login
        }

        $Status = "Created"
        $Message = "Usuário criado com sucesso."
    }
    catch {
        $Status = "Failed"
        $Message = $_.Exception.Message

        Write-Log "Erro ao criar usuário $Login. $_" "ERROR"
    }

    $Results += [PSCustomObject]@{
        Login = $Login
        Name = $FullName
        Department = $Department
        Title = $Title
        Status = $Status
        Message = $Message
    }
}

# ==============================
# Relatório
# ==============================

try {
    $Results | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8
    Write-Log "Relatório exportado: $ReportFile" "SUCCESS"
}
catch {
    Write-Log "Erro ao exportar relatório. $_" "ERROR"
}

$Created = ($Results | Where-Object {$_.Status -eq "Created"}).Count
$Skipped = ($Results | Where-Object {$_.Status -eq "Skipped"}).Count
$Failed  = ($Results | Where-Object {$_.Status -eq "Failed"}).Count

Write-Log "Resumo da execução:"
Write-Log "Criados: $Created"
Write-Log "Ignorados: $Skipped"
Write-Log "Falhas: $Failed"
Write-Log "Execução finalizada."
