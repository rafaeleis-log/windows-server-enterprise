<#
.SYNOPSIS
Enterprise Password Reset Script

.DESCRIPTION
Redefine senha, desbloqueia conta, força troca no próximo logon,
gera log e valida existência do usuário.

.AUTHOR
Rafael Ferreira Eis
#>

Import-Module ActiveDirectory

$Log=".\\PasswordReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Log($m){
$line="$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"
$line|Out-File -Append $Log
Write-Host $line
}

$user=Read-Host "Login do usuário"

try{
    $ad=Get-ADUser $user -Properties LockedOut -ErrorAction Stop
}
catch{
    Log "Usuário não encontrado."
    exit
}

if($ad.LockedOut){
    Unlock-ADAccount $user
    Log "Conta desbloqueada."
}

$pwd=Read-Host "Nova senha" -AsSecureString

try{
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $pwd
    Set-ADUser $user -ChangePasswordAtLogon $true
    Log "Senha redefinida com sucesso."
}
catch{
    Log "Erro ao redefinir senha: $_"
    exit
}

[pscustomobject]@{
Usuario=$user
Data=Get-Date
Status="Success"
}|Export-Csv ".\\PasswordResetReport.csv" -NoTypeInformation -Encoding UTF8

Log "Processo finalizado."
