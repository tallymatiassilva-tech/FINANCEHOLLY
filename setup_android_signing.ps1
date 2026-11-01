$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw 'keytool não encontrado. Instale um JDK e configure o PATH antes de continuar.'
}

$signingDirectory = Join-Path $env:LOCALAPPDATA 'ControleFinanceiroIgreja'
$keystorePath = Join-Path $signingDirectory 'release-key.jks'
$configurationDirectory = Join-Path $env:APPDATA 'ControleFinanceiroIgreja'
$configurationPath = Join-Path $configurationDirectory 'signing.json'
$keyAlias = 'pirituba-release'

if (Test-Path -LiteralPath $keystorePath) {
    throw "A keystore já existe em '$keystorePath'. Ela não será sobrescrita."
}
if (Test-Path -LiteralPath $configurationPath) {
    throw "A configuração de assinatura já existe em '$configurationPath'. Ela não será sobrescrita."
}

New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $configurationDirectory -Force | Out-Null

$randomBytes = New-Object byte[] 32
$randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $randomGenerator.GetBytes($randomBytes)
}
finally {
    $randomGenerator.Dispose()
}
$password = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
[Array]::Clear($randomBytes, 0, $randomBytes.Length)

$originalStorePassword = [Environment]::GetEnvironmentVariable('ANDROID_KEYSTORE_PASSWORD', 'Process')
$originalKeyPassword = [Environment]::GetEnvironmentVariable('ANDROID_KEY_PASSWORD', 'Process')
try {
    $env:ANDROID_KEYSTORE_PASSWORD = $password
    $env:ANDROID_KEY_PASSWORD = $password

    & $keytool.Source -genkeypair `
        -v `
        -keystore $keystorePath `
        -storetype JKS `
        -storepass:env ANDROID_KEYSTORE_PASSWORD `
        -alias $keyAlias `
        -keypass:env ANDROID_KEY_PASSWORD `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -dname 'CN=Controle Financeiro Igreja, OU=App, O=Pirituba, C=BR'
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível criar a keystore (código $LASTEXITCODE)."
    }

    $passwordBytes = [Text.Encoding]::UTF8.GetBytes($password)
    $encryptedPassword = [Convert]::ToBase64String(
        [Security.Cryptography.ProtectedData]::Protect(
            $passwordBytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    )
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    $configuration = [ordered]@{
        ANDROID_KEYSTORE_PATH = $keystorePath
        ANDROID_KEY_ALIAS = $keyAlias
        ANDROID_KEYSTORE_PASSWORD_ENCRYPTED = $encryptedPassword
        ANDROID_KEY_PASSWORD_ENCRYPTED = $encryptedPassword
    }
    $configuration | ConvertTo-Json | Set-Content -LiteralPath $configurationPath -Encoding UTF8
    $encryptedPassword = $null
}
finally {
    [Environment]::SetEnvironmentVariable('ANDROID_KEYSTORE_PASSWORD', $originalStorePassword, 'Process')
    [Environment]::SetEnvironmentVariable('ANDROID_KEY_PASSWORD', $originalKeyPassword, 'Process')
    $password = $null
}

Write-Output "Keystore criada em: $keystorePath"
Write-Output 'As senhas foram guardadas com proteção DPAPI para esta conta do Windows.'
Write-Output 'Faça uma cópia de segurança segura da keystore. Sem ela, não será possível assinar futuras atualizações com esta identidade.'
