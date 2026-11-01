$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    $flutterPath = Join-Path $env:LOCALAPPDATA 'Toolchains\flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $flutterPath -PathType Leaf) {
        $flutter = [pscustomobject]@{ Source = $flutterPath }
    }
    else {
        throw 'Flutter não encontrado. Instale o Flutter stable e o Android SDK antes de executar este script.'
    }
}

$root = $PSScriptRoot
$buildRoot = $root
$stagedBuild = $false
if ($root -match '[^\u0000-\u007F]') {
    $buildRoot = Join-Path $env:TEMP ("controle_financeiro_build_" + [guid]::NewGuid().ToString('N'))
    & robocopy $root $buildRoot /E /XD .git .dart_tool build .gradle .cxx .idea /XF *.apk *.aab /NFL /NDL /NJH /NJS /NC /NS
    if ($LASTEXITCODE -ge 8) {
        throw "Não foi possível preparar uma cópia de build sem caracteres especiais (código $LASTEXITCODE)."
    }
    $stagedBuild = $true
}
$temporaryProject = Join-Path $env:TEMP ("controle_financeiro_scaffold_" + [guid]::NewGuid().ToString('N'))
$signingVariables = @(
    'ANDROID_KEYSTORE_PATH',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD'
)
$originalSigningValues = @{}
foreach ($name in $signingVariables) {
    $originalSigningValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $signingConfigurationPath = Join-Path $env:APPDATA 'ControleFinanceiroIgreja\signing.json'
    if (Test-Path -LiteralPath $signingConfigurationPath -PathType Leaf) {
        $signingConfiguration = Get-Content -LiteralPath $signingConfigurationPath -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH)) {
            $env:ANDROID_KEYSTORE_PATH = $signingConfiguration.ANDROID_KEYSTORE_PATH
        }
        if ([string]::IsNullOrWhiteSpace($env:ANDROID_KEY_ALIAS)) {
            $env:ANDROID_KEY_ALIAS = $signingConfiguration.ANDROID_KEY_ALIAS
        }

        foreach ($entry in @(
            @{ Variable = 'ANDROID_KEYSTORE_PASSWORD'; Property = 'ANDROID_KEYSTORE_PASSWORD_ENCRYPTED' },
            @{ Variable = 'ANDROID_KEY_PASSWORD'; Property = 'ANDROID_KEY_PASSWORD_ENCRYPTED' }
        )) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($entry.Variable, 'Process'))) {
                $encrypted = $signingConfiguration.($entry.Property)
                if ([string]::IsNullOrWhiteSpace($encrypted)) {
                    throw "A configuração local de assinatura não contém $($entry.Property)."
                }
                $encryptedBytes = [Convert]::FromBase64String($encrypted)
                $passwordBytes = [Security.Cryptography.ProtectedData]::Unprotect(
                    $encryptedBytes,
                    $null,
                    [Security.Cryptography.DataProtectionScope]::CurrentUser
                )
                try {
                    [Environment]::SetEnvironmentVariable(
                        $entry.Variable,
                        [Text.Encoding]::UTF8.GetString($passwordBytes),
                        'Process'
                    )
                }
                finally {
                    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
                }
            }
        }
    }

    if (-not (Test-Path (Join-Path $buildRoot 'android')) -or -not (Test-Path (Join-Path $buildRoot 'ios'))) {
        & $flutter.Source create `
            --project-name controle_financeiro_igreja `
            --org br.org.pirituba `
            --platforms android,ios `
            $temporaryProject
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível gerar os diretórios nativos do Flutter (código $LASTEXITCODE)."
        }

        foreach ($platform in @('android', 'ios')) {
            $target = Join-Path $buildRoot $platform
            if (-not (Test-Path $target)) {
                Copy-Item -Path (Join-Path $temporaryProject $platform) -Destination $target -Recurse
            }
        }
        $metadata = Join-Path $temporaryProject '.metadata'
        if (-not (Test-Path (Join-Path $buildRoot '.metadata')) -and (Test-Path $metadata)) {
            Copy-Item -Path $metadata -Destination (Join-Path $buildRoot '.metadata')
        }
        $manifest = Join-Path $buildRoot 'android\app\src\main\AndroidManifest.xml'
        if (Test-Path $manifest) {
            $contents = Get-Content -LiteralPath $manifest -Raw
            $contents = $contents -replace 'android:label="[^"]+"', 'android:label="Controle Financeiro Igreja"'
            Set-Content -LiteralPath $manifest -Value $contents -Encoding utf8
        }
        $infoPlist = Join-Path $buildRoot 'ios\Runner\Info.plist'
        if (Test-Path $infoPlist) {
            $contents = Get-Content -LiteralPath $infoPlist -Raw
            $contents = $contents -replace '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', '${1}Controle Financeiro Igreja$2'
            Set-Content -LiteralPath $infoPlist -Value $contents -Encoding utf8
        }
    }

    Push-Location $buildRoot
    try {
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou (código $LASTEXITCODE)." }

        & $flutter.Source analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze encontrou problemas (código $LASTEXITCODE)." }

        $missingSigningVariables = @(
            $signingVariables | Where-Object {
                [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
            }
        )
        if ($missingSigningVariables.Count -gt 0) {
            throw "Configure as variáveis de assinatura de release: $($missingSigningVariables -join ', ')."
        }
        if (-not (Test-Path -LiteralPath $env:ANDROID_KEYSTORE_PATH -PathType Leaf)) {
            throw 'O arquivo definido em ANDROID_KEYSTORE_PATH não foi encontrado.'
        }

        & $flutter.Source build apk --release
        if ($LASTEXITCODE -ne 0) { throw "A compilação do APK falhou (código $LASTEXITCODE)." }
        if ($stagedBuild) {
            $sourceApk = Join-Path $buildRoot 'build\app\outputs\flutter-apk\app-release.apk'
            $targetDirectory = Join-Path $root 'build\app\outputs\flutter-apk'
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
            Copy-Item -LiteralPath $sourceApk -Destination $targetDirectory -Force
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    foreach ($name in $signingVariables) {
        [Environment]::SetEnvironmentVariable($name, $originalSigningValues[$name], 'Process')
    }
    if (Test-Path $temporaryProject) {
        Remove-Item -LiteralPath $temporaryProject -Recurse -Force
    }
    if ($stagedBuild -and (Test-Path $buildRoot)) {
        $cleanupOutput = & $env:ComSpec /c "rmdir /s /q `"$buildRoot`"" 2>&1
        if (Test-Path $buildRoot) {
            Write-Warning "A pasta temporária de build ainda está em uso e não pôde ser removida: $buildRoot`n$($cleanupOutput -join [Environment]::NewLine)"
        }
    }
}
