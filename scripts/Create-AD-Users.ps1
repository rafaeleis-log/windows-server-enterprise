# Create-AD-Users.ps1
# Exemplo de criação de usuários no Active Directory

Import-Module ActiveDirectory

$Users = Import-Csv ".\users.csv"

foreach ($User in $Users)
{
    New-ADUser `
        -Name $User.Name `
        -GivenName $User.FirstName `
        -Surname $User.LastName `
        -SamAccountName $User.Login `
        -UserPrincipalName "$($User.Login)@empresa.local" `
        -Enabled $true `
        -AccountPassword (ConvertTo-SecureString "Temp@12345" -AsPlainText -Force)
}
