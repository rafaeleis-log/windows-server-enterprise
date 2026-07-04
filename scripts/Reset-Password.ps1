Set-ADAccountPassword `
-Identity usuario `
-Reset `
-NewPassword (ConvertTo-SecureString "NovaSenha@123" -AsPlainText -Force)
