$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Split-Path $PSScriptRoot -Parent
$package=Join-Path $root 'build/package/Release/first-person'
$manifest=Get-Content -LiteralPath (Join-Path $package 'zml-package.json') -Raw -Encoding utf8 | ConvertFrom-Json
if($manifest.id -ne 'first-person-remix'){throw 'Wrong package'}
$ini=Get-Content -LiteralPath (Join-Path $package 'mod.ini') -Raw -Encoding utf8
if($ini -notmatch '(?m)^version=(\d+(?:\.\d+)+)\r?$'){throw 'Invalid version'}
$version=$Matches[1]
$dist=Join-Path $root 'dist';New-Item -ItemType Directory -Force $dist | Out-Null
$zip=Join-Path $dist ("EndfieldFirstPerson-$version-"+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
$names=@($manifest.files)+@('zml-package.json')
$seen=@{}
foreach($name in $names){
    if([IO.Path]::GetFileName($name) -ne $name -or $seen.ContainsKey($name) -or -not(Test-Path -LiteralPath (Join-Path $package $name) -PathType Leaf)){throw 'Unsafe, duplicate, or missing file'}
    $seen[$name]=$true
}
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($name in $names){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $package $name),$name)|Out-Null}}finally{$archive.Dispose()}
$sha=[Security.Cryptography.SHA256]::Create()
try{$hash=([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($zip)))).Replace('-','')}finally{$sha.Dispose()}
"$hash  $([IO.Path]::GetFileName($zip))" | Set-Content -Encoding ascii ($zip+'.sha256')
Write-Output $zip
