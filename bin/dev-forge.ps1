[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ForgeDir = (Get-Item $PSScriptRoot).Parent.FullName

function Write-Info { param([string]$msg) Write-Host "[dev-forge] $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "[dev-forge : OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[dev-forge : AVISO] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "[dev-forge : ERROR] $msg" -ForegroundColor Red }

function Show-Banner {
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "     ____  _______     __     _____ ___  ____   ____ _____ " -ForegroundColor Cyan
    Write-Host "    |  _ \| ____\ \   / /    |  ___/ _ \|  _ \ / ___| ____|" -ForegroundColor Cyan
    Write-Host "    | | | |  _|  \ \ / /_____| |_ | | | | |_) | |  _|  _|  " -ForegroundColor Cyan
    Write-Host "    | |_| | |___  \ V /|_____|  _|| |_| |  _ <| |_| | |___ " -ForegroundColor Cyan
    Write-Host "    |____/|_____|  \_/       |_|   \___/|_| \_\\____|_____|" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "       Forja Universal de Compilacion Multi-Lenguaje (100% Offline)`n" -ForegroundColor Gray
}

function Show-Help {
    Show-Banner
    Write-Host "USO:" -ForegroundColor White
    Write-Host "  dev-forge.ps1 <comando> [opciones]`n"
    Write-Host "COMANDOS:" -ForegroundColor White
    Write-Host "  build      Compila un proyecto externo en las VMs correspondientes" -ForegroundColor Green
    Write-Host "  status     Muestra el estado de las maquinas virtuales de la forja" -ForegroundColor Green
    Write-Host "  up         Inicia una maquina virtual (forge-linux | forge-windows)" -ForegroundColor Green
    Write-Host "  halt       Detiene las maquinas virtuales para liberar memoria" -ForegroundColor Green
    Write-Host "  provision  Re-aprovisiona las herramientas en las maquinas virtuales" -ForegroundColor Green
    Write-Host "  ssh        Abre una sesion interactiva en la VM (Linux)" -ForegroundColor Green
    Write-Host "`nOPCIONES DE 'build':" -ForegroundColor White
    Write-Host "  -p, --project <ruta>     Ruta al proyecto que se desea compilar (Obligatorio)"
    Write-Host "  -t, --target <destino>   Destino: linux | windows | macos | android | all (defecto: all)"
    Write-Host "  -c, --clean              Limpia caches intermedias antes de compilar"
    Write-Host "  -k, --keep-vm            Mantiene las VMs encendidas tras la compilacion"
    Write-Host "  -u, --update             Fuerza el re-aprovisionamiento de paquetes en la VM"
    Write-Host "  -h, --help               Muestra esta ayuda`n"
    Write-Host "EJEMPLOS:" -ForegroundColor White
    Write-Host "  .\dev-forge.ps1 build -p C:\proyectos\lexishield -t windows"
    Write-Host "  .\dev-forge.ps1 build -p C:\proyectos\lexishield -t linux"
    Write-Host "  .\dev-forge.ps1 build -p C:\proyectos\mi-app -t all`n"
}

function Detect-ProjectType {
    param([string]$Path)
    if (Test-Path (Join-Path $Path "Cargo.toml")) {
        if ((Test-Path (Join-Path $Path "src-tauri")) -or (Test-Path (Join-Path $Path "src-tauri\tauri.conf.json"))) {
            return "rust-tauri"
        }
        return "rust"
    }
    if ((Test-Path (Join-Path $Path "build.gradle")) -or (Test-Path (Join-Path $Path "build.gradle.kts")) -or (Test-Path (Join-Path $Path "gradlew.bat")) -or (Test-Path (Join-Path $Path "pom.xml")) -or (Test-Path (Join-Path $Path "src\main\java"))) {
        if ((Test-Path (Join-Path $Path "app\src\main")) -or (Select-String -Path (Join-Path $Path "build.gradle") -Pattern "com.android" -Quiet -ErrorAction SilentlyContinue)) {
            return "java-android"
        }
        return "java"
    }
    if ((Test-Path (Join-Path $Path "pyproject.toml")) -or (Test-Path (Join-Path $Path "requirements.txt")) -or (Test-Path (Join-Path $Path "main.py"))) {
        return "python"
    }
    if (Test-Path (Join-Path $Path "go.mod")) {
        return "go"
    }
    if (Test-Path (Join-Path $Path "package.json")) {
        return "node"
    }
    if ((Test-Path (Join-Path $Path "CMakeLists.txt")) -or (Test-Path (Join-Path $Path "Makefile"))) {
        return "c-cpp"
    }
    return "generic"
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1}G" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1}M" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0}K" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-HostKeyboardLayout {
    try {
        $langs = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        if ($langs -and $langs.Count -gt 0) {
            return $langs[0].LanguageTag
        }
    } catch {}
    try {
        return [System.Globalization.CultureInfo]::CurrentCulture.Name
    } catch {}
    return "es-ES"
}

function Invoke-Build {
    param([string[]]$ArgsList)

    $projectPath = ""
    $target = "all"
    $doClean = $false
    $keepVm = $false
    $doUpdate = $false

    $i = 0
    while ($i -lt $ArgsList.Count) {
        switch ($ArgsList[$i]) {
            { $_ -in "-p", "--project" } {
                $i++
                $projectPath = $ArgsList[$i]
            }
            { $_ -in "-t", "--target" } {
                $i++
                $target = $ArgsList[$i].ToLower()
            }
            { $_ -in "-c", "--clean" } {
                $doClean = $true
            }
            { $_ -in "-k", "--keep-vm" } {
                $keepVm = $true
            }
            { $_ -in "-u", "--update", "--provision" } {
                $doUpdate = $true
            }
            { $_ -in "-h", "--help" } {
                Show-Help
                return
            }
            default {
                Write-Err "Opcion desconocida: $($ArgsList[$i])"
                Show-Help
                exit 1
            }
        }
        $i++
    }

    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        Write-Err "Debe especificar la ruta del proyecto con -p o --project."
        exit 1
    }

    if (-not (Test-Path $projectPath)) {
        Write-Err "El directorio de proyecto '$projectPath' no existe."
        exit 1
    }

    $projectPath = (Resolve-Path $projectPath).Path
    $projectName = Split-Path -Leaf $projectPath
    $projectType = Detect-ProjectType -Path $projectPath

    Write-Info "Proyecto objetivo: $projectName ($projectPath)"
    Write-Info "Tipo detectado:    $projectType"
    Write-Info "Destino objetivo:  $target"

    if (-not $env:FORGE_HOST_KEYBOARD) {
        $env:FORGE_HOST_KEYBOARD = Get-HostKeyboardLayout
    }
    Write-Info "Teclado host:      $($env:FORGE_HOST_KEYBOARD)"

    $distPath = Join-Path $projectPath "dist"
    if (-not (Test-Path $distPath)) {
        New-Item -ItemType Directory -Force -Path $distPath | Out-Null
    }

    # Exportar variable de entorno para que el Vagrantfile monte el workspace
    $env:FORGE_WORKSPACE = $projectPath

    $needLinux = $false
    $needWindows = $false
    $needMacos = $false

    switch ($target) {
        "linux"   { $needLinux = $true }
        "windows" { $needWindows = $true }
        "macos"   { $needMacos = $true; $needLinux = $true }
        "android" { $needLinux = $true }
        "all"     { $needLinux = $true; $needWindows = $true; $needMacos = $true }
        default {
            Write-Err "Target no soportado: '$target'. Opciones: linux, windows, macos, android, all."
            exit 1
        }
    }

    # 1. EJECUCION EN FORGE-LINUX
    if ($needLinux) {
        Write-Host ""
        Write-Info "=== Preparando VM 'forge-linux' ==="
        Push-Location $ForgeDir
        try {
            if ($doUpdate) {
                & vagrant up forge-linux --provision
            } else {
                & vagrant up forge-linux
            }

            Write-Info "Ejecutando compilacion en forge-linux (/workspace)..."
            $linuxCmd = ""
            switch ($projectType) {
                "rust-tauri" {
                    $linuxCmd = "cd /workspace && export CARGO_TARGET_DIR=/tmp/cargo-target && if [ -f ui/package.json ]; then if [ ! -d ui/dist ]; then npm --prefix ui run build; fi; elif [ -f package.json ]; then if [ ! -d dist ]; then npm run build; fi; fi && cargo build --release && mkdir -p /workspace/dist && find /tmp/cargo-target/release -maxdepth 1 -type f \( -executable -o -name '*.so' -o -name '*.a' \) ! -name '*.d' -exec cp -f {} /workspace/dist/ \;"
                }
                "rust" {
                    $linuxCmd = "cd /workspace && export CARGO_TARGET_DIR=/tmp/cargo-target && cargo build --release && mkdir -p /workspace/dist && find /tmp/cargo-target/release -maxdepth 1 -type f \( -executable -o -name '*.so' -o -name '*.a' \) ! -name '*.d' -exec cp -f {} /workspace/dist/ \;"
                }
                "java-android" {
                    $linuxCmd = "cd /workspace && if [ -f ./gradlew ]; then chmod +x ./gradlew && (./gradlew assembleRelease || ./gradlew assembleDebug); else (gradle assembleRelease || gradle assembleDebug); fi && mkdir -p /workspace/dist && find app/build/outputs/apk -name '*.apk' -exec cp -f {} /workspace/dist/ \; 2>/dev/null || true"
                }
                "java" {
                    $linuxCmd = "cd /workspace && if [ -f ./gradlew ]; then chmod +x ./gradlew && ./gradlew build; elif [ -f build.gradle ]; then gradle build; else mkdir -p build/classes /workspace/dist && javac -d build/classes `$(find src -name '*.java') && jar cfe /workspace/dist/hashforge-java.jar com.devforge.hashforge.Main -C build/classes . ; fi && mkdir -p /workspace/dist && find build/libs -name '*.jar' ! -name '*-plain.jar' -exec cp -f {} /workspace/dist/ \; 2>/dev/null || true"
                }
                "python" {
                    $pyName = if ($projectName -eq "python") { "hashforge-py" } else { $projectName }
                    $linuxCmd = "cd /workspace && if [ -f main.py ]; then pyinstaller --onefile --name '$pyName' --distpath /workspace/dist main.py; else python3 -m pip install -e .; fi"
                }
                "go" {
                    $goName = if ($projectName -eq "go") { "hashforge-go" } else { $projectName }
                    $linuxCmd = "cd /workspace && mkdir -p /workspace/dist && go build -ldflags='-s -w' -o '/workspace/dist/$goName' ./"
                }
                "node" {
                    $linuxCmd = "cd /workspace && if [ -f package-lock.json ]; then npm ci 2>/dev/null || npm install; elif [ -f package.json ]; then npm install 2>/dev/null || true; fi && if grep -q '\"build\":' package.json 2>/dev/null; then npm run build; fi && mkdir -p /workspace/dist && if [ -d dist ]; then cp -rf dist/* /workspace/dist/ 2>/dev/null || true; elif [ -f index.js ]; then cp -f index.js /workspace/dist/hashforge-node.js; fi"
                }
                "c-cpp" {
                    $linuxCmd = "cd /workspace && if [ -f CMakeLists.txt ] && command -v cmake >/dev/null 2>&1; then cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build && mkdir -p /workspace/dist && find build -maxdepth 2 -type f \( -executable -o -name '*.so' -o -name '*.a' \) ! -name '*.sh' ! -name '*.txt' ! -name '*.cmake' -exec cp -f {} /workspace/dist/ \;; elif [ -f Makefile ]; then make && mkdir -p /workspace/dist && for f in *; do if [ -f \"\$f\" ] && [ -x \"\$f\" ] && file \"\$f\" | grep -q 'ELF'; then cp -f \"\$f\" /workspace/dist/; fi; done; fi"
                }
                default {
                    $linuxCmd = "cd /workspace && if [ -f Makefile ]; then make; fi"
                }
            }

            if ($doClean) {
                $linuxCmd = "rm -rf /tmp/cargo-target /workspace/target 2>/dev/null || true; cargo clean 2>/dev/null || true; $linuxCmd"
            }

            & vagrant ssh forge-linux -c "$linuxCmd"
            Write-Ok "Compilacion en forge-linux finalizada."

            if ($needMacos) {
                Write-Info "Ejecutando compilacion cruzada para macOS via Docker/osxcross en forge-linux..."
                $macCmd = "cd /workspace && if [ -f Cargo.toml ]; then export CARGO_TARGET_DIR=/tmp/cargo-target && cargo build --release --target x86_64-apple-darwin 2>/dev/null && mkdir -p /workspace/dist && find /tmp/cargo-target/x86_64-apple-darwin/release -maxdepth 1 -type f ! -name '*.d' ! -name '*.rlib' -exec cp -f {} /workspace/dist/ \; || true; fi"
                & vagrant ssh forge-linux -c "$macCmd"
            }

            if (-not $keepVm) {
                Write-Info "Deteniendo 'forge-linux' para liberar memoria..."
                & vagrant halt forge-linux
            }
        } finally {
            Pop-Location
        }
    }

    # 2. EJECUCION EN FORGE-WINDOWS
    if ($needWindows) {
        Write-Host ""
        Write-Info "=== Preparando VM 'forge-windows' ==="
        Push-Location $ForgeDir
        try {
            if ($doUpdate) {
                & vagrant up forge-windows --provision
            } else {
                & vagrant up forge-windows
            }

            Write-Info "Ejecutando compilacion nativa en forge-windows (c:\workspace)..."
            $winCmd = ""
            switch ($projectType) {
                "rust-tauri" {
                    $winCmd = "Set-Location c:\workspace; [Environment]::SetEnvironmentVariable('CARGO_TARGET_DIR', 'c:\target'); if (Test-Path ui\package.json) { if (-not (Test-Path ui\dist)) { if (-not (Test-Path ui\node_modules\.bin\vite.cmd)) { npm --prefix ui install }; npm --prefix ui run build } } elseif (Test-Path package.json) { if (-not (Test-Path dist)) { if (-not (Test-Path node_modules)) { npm install }; npm run build } }; cargo build --release; if (Test-Path c:\target\release) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem c:\target\release -Filter *.exe | Copy-Item -Destination c:\workspace\dist\ -Force; Get-ChildItem c:\target\release -Filter *.dll | Copy-Item -Destination c:\workspace\dist\ -Force }"
                }
                "rust" {
                    $winCmd = "Set-Location c:\workspace; [Environment]::SetEnvironmentVariable('CARGO_TARGET_DIR', 'c:\target'); cargo build --release; if (Test-Path c:\target\release) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem c:\target\release -Filter *.exe | Copy-Item -Destination c:\workspace\dist\ -Force; Get-ChildItem c:\target\release -Filter *.dll | Copy-Item -Destination c:\workspace\dist\ -Force }"
                }
                "java" {
                    $winCmd = "Set-Location c:\workspace; if (Test-Path gradlew.bat) { .\gradlew.bat build } elseif (Test-Path build.gradle) { gradle build } else { New-Item -ItemType Directory -Force -Path build\classes, c:\workspace\dist | Out-Null; javac -d build\classes (Get-ChildItem -Recurse -Filter *.java src | ForEach-Object { `$_.FullName }); jar cfe c:\workspace\dist\hashforge-java.jar com.devforge.hashforge.Main -C build\classes . }; if (Test-Path build\libs) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem build\libs -Filter *.jar | Where-Object { `$_.Name -notlike '*-plain.jar' } | Copy-Item -Destination c:\workspace\dist\ -Force }"
                }
                "java-android" {
                    $winCmd = "Set-Location c:\workspace; if (Test-Path gradlew.bat) { .\gradlew.bat assembleRelease } else { gradle assembleRelease }; if (Test-Path app\build\outputs\apk) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem -Recurse app\build\outputs\apk -Filter *.apk | Copy-Item -Destination c:\workspace\dist\ -Force }"
                }
                "python" {
                    $pyName = if ($projectName -eq "python") { "hashforge-py" } else { $projectName }
                    $winCmd = "Set-Location c:\workspace; if (Test-Path main.py) { pyinstaller --onefile --name '$pyName' --distpath c:\workspace\dist main.py }"
                }
                "go" {
                    $goName = if ($projectName -eq "go") { "hashforge-go" } else { $projectName }
                    $winCmd = "Set-Location c:\workspace; New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; go build -ldflags=""-s -w"" -o c:\workspace\dist\$goName.exe ./"
                }
                "node" {
                    $winCmd = "Set-Location c:\workspace; if (Test-Path package-lock.json) { npm ci } elseif (Test-Path package.json) { npm install }; if (Select-String -Path package.json -Pattern '`"build`":' -Quiet -ErrorAction SilentlyContinue) { npm run build }; New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; if (Test-Path dist) { Copy-Item -Recurse -Force dist\* c:\workspace\dist\ } elseif (Test-Path index.js) { Copy-Item -Force index.js c:\workspace\dist\hashforge-node.js }"
                }
                "c-cpp" {
                    $winCmd = "Set-Location c:\workspace; if (Test-Path CMakeLists.txt) { cmake -B build; cmake --build build --config Release; if (Test-Path build\Release) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem build\Release -Filter *.exe | Copy-Item -Destination c:\workspace\dist\ -Force; Get-ChildItem build\Release -Filter *.dll | Copy-Item -Destination c:\workspace\dist\ -Force } elseif (Test-Path build) { New-Item -ItemType Directory -Force -Path c:\workspace\dist | Out-Null; Get-ChildItem build -Filter *.exe | Copy-Item -Destination c:\workspace\dist\ -Force } } elseif (Test-Path Makefile) { nmake }"
                }
                default {
                    $winCmd = "Write-Host 'No se reconocio comando especifico para este tipo en Windows.'"
                }
            }

            if ($doClean) {
                $winCmd = "if (Test-Path c:\target) { Remove-Item -Recurse -Force c:\target -ErrorAction SilentlyContinue }; if (Test-Path c:\workspace\target) { Remove-Item -Recurse -Force c:\workspace\target -ErrorAction SilentlyContinue }; $winCmd"
            }

            & vagrant winrm forge-windows -c "powershell -ExecutionPolicy Bypass -Command `"$winCmd`""
            Write-Ok "Compilacion en forge-windows finalizada."

            if (-not $keepVm) {
                Write-Info "Deteniendo 'forge-windows' para liberar memoria..."
                & vagrant halt forge-windows
            }
        } finally {
            Pop-Location
        }
    }

    Write-Host ""
    Write-Ok "Proceso completado con exito. Revisa los binarios generados en: $distPath"
    if (Test-Path $distPath) {
        $files = Get-ChildItem -Path $distPath -File
        if ($files.Count -gt 0) {
            Write-Host "`n  Artefactos en dist/ ($($files.Count)):" -ForegroundColor Cyan
            foreach ($file in $files) {
                $sizeStr = Format-FileSize -Bytes $file.Length
                Write-Host "   ✔ " -NoNewline -ForegroundColor Green
                Write-Host ("{0,-40}" -f $file.Name) -NoNewline
                Write-Host " ($sizeStr)" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
}

# Enrutador principal
$cmd = if ($args.Count -gt 0) { $args[0] } else { "" }
$remainingArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($cmd) {
    "build" {
        Invoke-Build -ArgsList $remainingArgs
    }
    "status" {
        Push-Location $ForgeDir
        try { & vagrant status } finally { Pop-Location }
    }
    "up" {
        Push-Location $ForgeDir
        try { & vagrant up @remainingArgs } finally { Pop-Location }
    }
    "halt" {
        Push-Location $ForgeDir
        try { & vagrant halt @remainingArgs } finally { Pop-Location }
    }
    "provision" {
        Push-Location $ForgeDir
        try { & vagrant provision @remainingArgs } finally { Pop-Location }
    }
    "ssh" {
        Push-Location $ForgeDir
        try { & vagrant ssh forge-linux @remainingArgs } finally { Pop-Location }
    }
    { $_ -in "-h", "--help", "help", "" } {
        Show-Help
    }
    default {
        Write-Err "Comando no reconocido: '$cmd'"
        Show-Help
        exit 1
    }
}

