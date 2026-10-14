$ErrorActionPreference = 'Stop'

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw 'Flutter não encontrado. Instale o Flutter stable e o Android SDK antes de executar este script.'
}

$root = $PSScriptRoot
$temporaryProject = Join-Path $env:TEMP ("controle_financeiro_scaffold_" + [guid]::NewGuid().ToString('N'))

try {
    if (-not (Test-Path (Join-Path $root 'android')) -or -not (Test-Path (Join-Path $root 'ios'))) {
        & $flutter.Source create `
            --project-name controle_financeiro_igreja `
            --org br.org.pirituba `
            --platforms android,ios `
            $temporaryProject
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível gerar os diretórios nativos do Flutter (código $LASTEXITCODE)."
        }

        foreach ($platform in @('android', 'ios')) {
            $target = Join-Path $root $platform
            if (-not (Test-Path $target)) {
                Copy-Item -Path (Join-Path $temporaryProject $platform) -Destination $target -Recurse
            }
        }
        $metadata = Join-Path $temporaryProject '.metadata'
        if (-not (Test-Path (Join-Path $root '.metadata')) -and (Test-Path $metadata)) {
            Copy-Item -Path $metadata -Destination (Join-Path $root '.metadata')
        }
        $manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
        if (Test-Path $manifest) {
            $contents = Get-Content -LiteralPath $manifest -Raw
            $contents = $contents -replace 'android:label="[^"]+"', 'android:label="Controle Financeiro Igreja"'
            Set-Content -LiteralPath $manifest -Value $contents -Encoding utf8
        }
        $infoPlist = Join-Path $root 'ios\Runner\Info.plist'
        if (Test-Path $infoPlist) {
            $contents = Get-Content -LiteralPath $infoPlist -Raw
            $contents = $contents -replace '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', '${1}Controle Financeiro Igreja$2'
            Set-Content -LiteralPath $infoPlist -Value $contents -Encoding utf8
        }
    }

    Push-Location $root
    try {
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou (código $LASTEXITCODE)." }

        & $flutter.Source analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze encontrou problemas (código $LASTEXITCODE)." }

        $signingVariables = @(
            'ANDROID_KEYSTORE_PATH',
            'ANDROID_KEYSTORE_PASSWORD',
            'ANDROID_KEY_ALIAS',
            'ANDROID_KEY_PASSWORD'
        )
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
    }
    finally {
        Pop-Location
    }
}
finally {
    if (Test-Path $temporaryProject) {
        Remove-Item -LiteralPath $temporaryProject -Recurse -Force
    }
}
