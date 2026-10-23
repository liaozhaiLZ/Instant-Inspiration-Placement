# ============================================================
# 灵感速记 · 手机版 —— 不用 Gradle 的 APK 构建脚本
#
# 只需要两样东西：
#   1) JDK 17（javac / java / keytool 在 PATH 里，或设置 JAVA_HOME）
#   2) Android SDK（只需 platforms + build-tools，不需要 Android Studio 工程向导）
#
# 用法（在 PowerShell 里执行）：
#   .\build-apk.ps1                                  # 自动找 SDK
#   .\build-apk.ps1 -Sdk "D:\Android\Sdk"            # 指定 SDK
#   .\build-apk.ps1 -Sdk "D:\Android\Sdk" -Out "D:\灵感速记.apk"
#
# 成功后会在项目根目录生成 灵感速记.apk（已签名，可直接安装）。
# ============================================================

[CmdletBinding()]
param(
    [string]$Sdk = "",
    [string]$Out = "",
    [string]$BuildTools = "",
    [string]$Platform = "",
    [switch]$KeepBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appDir = Join-Path $root 'app'
$build  = Join-Path $root 'build'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "构建失败：$msg" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Info([string]$msg) { Write-Host "  $msg" -ForegroundColor DarkGray }

# ---------- 1. 找 JDK ----------
Write-Host "[1/7] 检查 JDK" -ForegroundColor Cyan
$javac = $null
$javacCmd = (Get-Command javac -ErrorAction SilentlyContinue)
if ($javacCmd) { $javacPath = $javacCmd.Source }
if (-not $javacPath -and $env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME 'bin\javac.exe'
    if (Test-Path $candidate) { $javacPath = $candidate }
}
if (-not $javacPath) {
    Fail "找不到 javac。请安装 JDK 17（如 https://adoptium.net ），或把 JDK 的 bin 目录加入 PATH。"
}
$javaBin = Split-Path -Parent $javacPath
Info "javac: $javacPath"
$keytool = Join-Path $javaBin 'keytool.exe'
if (-not (Test-Path $keytool)) { $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source }
if (-not $keytool) { Fail "找不到 keytool（通常和 javac 在同一个 bin 目录里）。" }

# ---------- 2. 找 Android SDK ----------
Write-Host "[2/7] 检查 Android SDK" -ForegroundColor Cyan
if (-not $Sdk) {
    foreach ($p in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\AppData\Local\Android\Sdk")) {
        if ($p -and (Test-Path $p)) { $Sdk = $p; break }
    }
}
if (-not $Sdk -or -not (Test-Path $Sdk)) {
    Fail "找不到 Android SDK。请安装 Android Studio（装完自带 SDK），或用 -Sdk 指定目录。"
}
Info "SDK: $Sdk"

if (-not $BuildTools) {
    $bt = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
          Sort-Object { [version]($_.Name -replace '[^\d\.].*$', '') } -Descending | Select-Object -First 1
    if ($bt) { $BuildTools = $bt.FullName }
}
if (-not $BuildTools -or -not (Test-Path $BuildTools)) { Fail "找不到 build-tools（SDK Manager 里装一个 34.x 版本）。" }
Info "build-tools: $BuildTools"

if (-not $Platform) {
    $pf = Get-ChildItem (Join-Path $Sdk 'platforms') -Directory -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
    if ($pf) { $Platform = $pf.FullName }
}
if (-not $Platform -or -not (Test-Path $Platform)) { Fail "找不到 platforms\android-XX（SDK Manager 里装 Platform 34）。" }
$androidJar = Join-Path $Platform 'android.jar'
if (-not (Test-Path $androidJar)) { Fail "找不到 $androidJar" }
Info "platform: $Platform"

$aapt2    = Join-Path $BuildTools 'aapt2.exe'
$d8       = Join-Path $BuildTools 'd8.bat'
$zipalign = Join-Path $BuildTools 'zipalign.exe'
$apksigner = Join-Path $BuildTools 'apksigner.bat'
foreach ($tool in @($aapt2, $d8, $zipalign, $apksigner)) {
    if (-not (Test-Path $tool)) { Fail "build-tools 里缺少 $([System.IO.Path]::GetFileName($tool))" }
}

# 原生构建工具（aapt2 / zipalign / d8）不接受中文路径：
# 工程在中文目录时自动搬到临时英文目录编译，SDK 本身有中文则直接提示改路径。
function Test-Ascii([string]$text) {
    if (-not $text) { return $true }
    foreach ($ch in $text.ToCharArray()) { if ([int]$ch -gt 127) { return $false } }
    return $true
}

if (-not (Test-Ascii $Sdk)) {
    Fail "SDK 路径里有中文（$Sdk）。aapt2 / zipalign 无法处理中文路径，请把 Android SDK 换成纯英文路径后重试。"
}

if (-not $env:LINGAN_ASCII_BUILD -and -not (Test-Ascii $root)) {
    Write-Host "工程所在路径含中文，自动改到临时英文目录编译（编译完会把 apk 拷回来）" -ForegroundColor Yellow
    $tmpRoot = Join-Path $env:TEMP ('lingan_apk_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    Copy-Item (Join-Path $root 'app') -Destination $tmpRoot -Recurse
    Copy-Item $PSCommandPath (Join-Path $tmpRoot 'build-apk.ps1')
    $innerOut = Join-Path $tmpRoot 'out.apk'
    # 让每次构建复用同一把签名钥匙：把工程里已有的钥匙带进临时目录，构建完再带回来
    $ksName = 'debug' + '.keystore'
    $ksReal = Join-Path $root $ksName
    $ksTemp = Join-Path $tmpRoot $ksName
    if (Test-Path $ksReal) { Copy-Item $ksReal $ksTemp -Force }
    $env:LINGAN_ASCII_BUILD = '1'
    $innerArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $tmpRoot 'build-apk.ps1'), '-Sdk', $Sdk, '-Out', $innerOut)
    if ($BuildTools) { $innerArgs += @('-BuildTools', $BuildTools) }
    if ($Platform) { $innerArgs += @('-Platform', $Platform) }
    & powershell.exe @innerArgs
    $innerCode = $LASTEXITCODE
    if ($innerCode -eq 0 -and (Test-Path $innerOut)) {
        if (-not $Out) { $Out = Join-Path (Split-Path -Parent $root) '灵感速记.apk' }
        if (Test-Path $Out) { Remove-Item $Out -Force }
        Copy-Item $innerOut $Out -Force
        if ((Test-Path $ksTemp) -and -not (Test-Path $ksReal)) { Copy-Item $ksTemp $ksReal -Force }
        Write-Host ""
        Write-Host "构建完成：$Out （$([math]::Round((Get-Item $Out).Length / 1MB, 2)) MB）" -ForegroundColor Green
    }
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\LINGAN_ASCII_BUILD -ErrorAction SilentlyContinue
    exit $innerCode
}

# ---------- 3. 准备构建目录 ----------
Write-Host "[3/7] 准备构建目录" -ForegroundColor Cyan
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
$genDir    = Join-Path $build 'gen'
$classesDir = Join-Path $build 'classes'
$dexDir    = Join-Path $build 'dex'
$resZip    = Join-Path $build 'res.zip'
$unsigned  = Join-Path $build 'unsigned.apk'
$aligned   = Join-Path $build 'aligned.apk'
$classesJar = Join-Path $build 'classes.jar'
foreach ($d in @($genDir, $classesDir, $dexDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

# ---------- 4. 资源与 R.java ----------
Write-Host "[4/7] 编译资源（aapt2）" -ForegroundColor Cyan
& $aapt2 compile --dir (Join-Path $appDir 'src\main\res') -o $resZip
if ($LASTEXITCODE -ne 0) { Fail "aapt2 compile 失败（退出码 $LASTEXITCODE）" }

& $aapt2 link -o $unsigned -I $androidJar --manifest (Join-Path $appDir 'src\main\AndroidManifest.xml') `
    -R $resZip --java $genDir -A (Join-Path $appDir 'src\main\assets') `
    --min-sdk-version 23 --target-sdk-version 34 --auto-add-overlay
if ($LASTEXITCODE -ne 0) { Fail "aapt2 link 失败（退出码 $LASTEXITCODE）" }
Info "资源已打包，且已生成 R.java"

# ---------- 5. 编译 Java ----------
Write-Host "[5/7] 编译 Java 并转 dex" -ForegroundColor Cyan
$sources = @()
$sources += Get-ChildItem (Join-Path $appDir 'src\main\java') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$sources += Get-ChildItem $genDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if ($sources.Count -eq 0) { Fail "没有找到 Java 源码" }

& $javacPath -encoding UTF-8 -source 8 -target 8 -bootclasspath $androidJar -classpath $androidJar -d $classesDir @sources
if ($LASTEXITCODE -ne 0) { Fail "javac 编译失败（退出码 $LASTEXITCODE）" }

$jarExe = Join-Path $javaBin 'jar.exe'
Push-Location $classesDir
try { & $jarExe -cf $classesJar . } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { Fail "打包 classes.jar 失败" }
Info "已编译 $($sources.Count) 个 Java 文件"

& $d8 --release --lib $androidJar --min-api 23 --output $dexDir $classesJar
if ($LASTEXITCODE -ne 0) { Fail "d8 转 dex 失败（退出码 $LASTEXITCODE）" }
$dexFile = Join-Path $dexDir 'classes.dex'
if (-not (Test-Path $dexFile)) { Fail "d8 没有生成 classes.dex" }

# ---------- 6. 把 classes.dex 塞进 APK ----------
Write-Host "[6/7] 合并 dex 并做 4 字节对齐" -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsigned, 'Update')
try {
    $existing = $zip.GetEntry('classes.dex')
    if ($existing) { $existing.Delete() }
    $entry = $zip.CreateEntry('classes.dex', [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $bytes = [System.IO.File]::ReadAllBytes($dexFile)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Dispose()
} finally { $zip.Dispose() }

& $zipalign -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { Fail "zipalign 失败（退出码 $LASTEXITCODE）" }

# ---------- 7. 签名 ----------
Write-Host "[7/7] 生成密钥并签名" -ForegroundColor Cyan
$keystore = Join-Path $root 'debug.keystore'
if (-not (Test-Path $keystore)) {
    & $keytool -genkeypair -keystore $keystore -alias androiddebugkey `
        -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Lingan QuickNote, O=Local, C=CN"
    if ($LASTEXITCODE -ne 0) { Fail "生成签名密钥失败" }
    Info "已生成 debug.keystore（仅本地自用，正式上架请换成自己的密钥）"
}

if (-not $Out) { $Out = Join-Path (Split-Path -Parent $root) '灵感速记.apk' }
if (Test-Path $Out) { Remove-Item $Out -Force }

& $apksigner sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out $Out $aligned
if ($LASTEXITCODE -ne 0) { Fail "apksigner 签名失败（退出码 $LASTEXITCODE）" }

& $apksigner verify --verbose $Out | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "签名校验没通过" }

if (-not $KeepBuild) { Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue }

$sizeMb = [math]::Round((Get-Item $Out).Length / 1MB, 2)
Write-Host ""
Write-Host "构建完成：$Out （$sizeMb MB）" -ForegroundColor Green
Write-Host "把这个 .apk 传到手机点击安装即可；首次安装需要允许「安装未知来源应用」。" -ForegroundColor Gray
