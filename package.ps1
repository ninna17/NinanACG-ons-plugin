# 把上游编译出的 native 库打成 ninanapp 的 ONS 插件 zip（在 Windows 宿主上运行）。
# 另外会把 src\ 下的 GPL Java（OnsEngine、SafFile）编成 classes.dex 放进插件，所以需要先 flutter build 过宿主。
# 用法: powershell -File package.ps1 -Apk <app-release-unsigned.apk 或 debug.apk> -Version 1.0.0 -Out <输出目录>
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$Out,
    # 取 3 而不是 4：旧版 APP（接口 3）自带 ONS 的 Java 层，只读 plugin.json 里的 nativeLibs 并忽略 classes.dex，
    # 同一个 zip 在旧 APP 上照常使用；新 APP（接口 4）则改用 dex 里的 OnsEngine。
    [int]$MinHostApi = 3
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 依赖在前，主库 onsyuri 在最后；SDL 主库路径取自最后一项
$loadOrder = @('libSDL2.so', 'libSDL2_image.so', 'libSDL2_mixer.so', 'libSDL2_ttf.so',
               'libjpeg.so', 'liblua.so', 'libbz2.so', 'libonsyuri.so')
$abis = @('arm64-v8a', 'x86_64')

# ---- 编译插件 Java -> classes.dex ----
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$androidJar = Get-ChildItem (Join-Path $sdk 'platforms') -Directory | Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'android.jar' } | Where-Object { Test-Path $_ } | Select-Object -First 1
$d8 = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'd8.bat' } | Where-Object { Test-Path $_ } | Select-Object -First 1
$hostClasses = Join-Path $PSScriptRoot '..\..\build\app\tmp\kotlin-classes\debug' | Resolve-Path
$hostIface = Join-Path $PSScriptRoot '..\..\android\app\src\main\java\acg\ninan\uk\emu\EmuOnsBackend.java' | Resolve-Path
$gradle = Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1'
$stdlib = Get-ChildItem (Join-Path $gradle 'org.jetbrains.kotlin\kotlin-stdlib') -Recurse -Filter 'kotlin-stdlib-*.jar' |
    Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -First 1
if (-not $androidJar -or -not $d8 -or -not $stdlib) { throw "缺少 android.jar / d8 / kotlin-stdlib" }

$work = Join-Path $env:TEMP ("ons_dex_" + [guid]::NewGuid().ToString('N'))
$ifaceOut = Join-Path $work 'iface'; $classes = Join-Path $work 'classes'; $dexOut = Join-Path $work 'dex'; $libs = Join-Path $work 'libs'
New-Item -ItemType Directory -Force -Path $ifaceOut, $classes, $dexOut, $libs | Out-Null
# androidx 的 documentfile / core / annotation：宿主运行时已带，编译时从 gradle 缓存取
$cp = @("$hostClasses", $ifaceOut, $stdlib.FullName)
foreach ($lib in @('androidx.documentfile\documentfile', 'androidx.core\core', 'androidx.annotation\annotation')) {
    $f = Get-ChildItem (Join-Path $gradle $lib) -Recurse -Include *.aar, *.jar -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'sources|javadoc' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { throw "gradle 缓存里找不到 $lib" }
    if ($f.Extension -eq '.aar') {
        $dst = Join-Path $libs ($f.BaseName + '.jar')
        $zip = [System.IO.Compression.ZipFile]::OpenRead($f.FullName)
        try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry('classes.jar'), $dst, $true) } finally { $zip.Dispose() }
        $cp += $dst
    } else { $cp += $f.FullName }
}
$cpStr = $cp -join ';'
& javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options -bootclasspath $androidJar -cp "$hostClasses;$($stdlib.FullName)" -d $ifaceOut $hostIface
if ($LASTEXITCODE -ne 0) { throw 'javac(接口) 失败' }
$sources = Get-ChildItem (Join-Path $PSScriptRoot 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options -bootclasspath $androidJar -cp $cpStr -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw 'javac 失败' }
$classFiles = Get-ChildItem $classes -Recurse -Filter *.class | ForEach-Object { $_.FullName }
$d8Args = @('--release', '--min-api', '24', '--lib', $androidJar, '--output', $dexOut)
foreach ($c in $cp) { $d8Args += @('--classpath', $c) }
& $d8 @d8Args @classFiles
if ($LASTEXITCODE -ne 0) { throw 'd8 失败' }

$stage = Join-Path $env:TEMP ("ons_plugin_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '^lib/([^/]+)/([^/]+\.so)$' -and $abis -contains $Matches[1]) {
                $target = Join-Path $stage ("lib/" + $Matches[1])
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $target $Matches[2]), $true)
            }
        }
    } finally { $zip.Dispose() }

    Copy-Item (Join-Path $dexOut 'classes.dex') (Join-Path $stage 'classes.dex')
    # GPL 要求随二进制附带协议全文和源码获取方式
    # SOURCE.md 不进源码仓库（package.ps1 依赖它），缺了就直接报错，不要打出一个没有声明的包
    foreach ($notice in @('LICENSE', 'SOURCE.md')) {
        $noticePath = Join-Path $PSScriptRoot $notice
        if (-not (Test-Path $noticePath)) {
            throw "缺少 $notice（GPL 要求随插件包分发协议全文与源码获取方式）。SOURCE.md 不随源码仓库发布，请从 ninanapp/emu_plugins/ons/ 拷一份到 $PSScriptRoot"
        }
        Copy-Item $noticePath (Join-Path $stage $notice)
    }

    foreach ($abi in $abis) {
        foreach ($lib in $loadOrder) {
            if (-not (Test-Path (Join-Path $stage "lib/$abi/$lib"))) { throw "APK 缺少 $abi/$lib" }
        }
    }

    $meta = [ordered]@{
        id = 'ons'; engine = 'ons'; version = $Version; minHostApi = $MinHostApi
        entryClass = 'acg.ninan.uk.emu.plugin.ons.OnsEngine'; nativeLibs = $loadOrder
    }
    # 不带 BOM 的 UTF-8，APP 端用 JSONObject 解析
    [System.IO.File]::WriteAllText((Join-Path $stage 'plugin.json'), ($meta | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))

    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    $zipPath = Join-Path $Out "ons-$Version.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    # 不能用 CreateFromDirectory：Windows PowerShell 5.1 (.NET Framework) 会把条目路径写成反斜杠，Android 上会解出名字带 \ 的文件
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $root = (Resolve-Path $stage).Path.TrimEnd('\')
        Get-ChildItem $stage -Recurse -File | ForEach-Object {
            $entryName = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item $zipPath).Length
    Write-Output "插件: $zipPath"
    Write-Output "sha256: $hash"
    Write-Output "size: $size"
} finally {
    Remove-Item -Recurse -Force $stage, $work -ErrorAction SilentlyContinue
}
