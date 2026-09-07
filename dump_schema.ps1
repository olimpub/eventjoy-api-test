[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ConnectionInfo') | Out-Null

$serverName = "pulsator-prod.database.windows.net"
$dbName = "eventjoy-test"
$user = "pulsator_root"
$password = "8sHFdrCp7u"

$conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
$conn.ServerInstance = $serverName
$conn.LoginSecure = $false
$conn.Login = $user
$conn.Password = $password

Write-Host "Connecting to SQL Server..."
$server = New-Object Microsoft.SqlServer.Management.Smo.Server($conn)
$db = $server.Databases[$dbName]

$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($server)
$scripter.Options.ScriptSchema = $true
$scripter.Options.ScriptData = $false
$scripter.Options.IncludeHeaders = $false
$scripter.Options.Indexes = $true
$scripter.Options.DriAllConstraints = $true
$scripter.Options.EnforceScriptingOptions = $true

Write-Host "Fetching Tables..."
$tables = $db.Tables | Where-Object { $_.Schema -in @('EJ', 'PTA', 'dbo') -and $_.IsSystemObject -eq $false }
$outDirTables = "C:\Dev\VsCode\EventJoy.Api\SQL\Tables"
if (!(Test-Path $outDirTables)) { New-Item -ItemType Directory -Force -Path $outDirTables | Out-Null }

foreach ($t in $tables) {
    $script = $scripter.EnumScript($t)
    $filePath = Join-Path $outDirTables "$($t.Schema).$($t.Name).sql"
    Set-Content -Path $filePath -Value ($script -join "`r`nGO`r`n") -Encoding UTF8
}
Write-Host "Exported $($tables.Count) Tables."

Write-Host "Fetching Functions..."
$functions = $db.UserDefinedFunctions | Where-Object { $_.Schema -in @('EJ', 'PTA', 'dbo') -and $_.IsSystemObject -eq $false }
$outDirFuncs = "C:\Dev\VsCode\EventJoy.Api\SQL\Functions"
if (!(Test-Path $outDirFuncs)) { New-Item -ItemType Directory -Force -Path $outDirFuncs | Out-Null }

foreach ($f in $functions) {
    $script = $scripter.EnumScript($f)
    $filePath = Join-Path $outDirFuncs "$($f.Schema).$($f.Name).sql"
    Set-Content -Path $filePath -Value ($script -join "`r`nGO`r`n") -Encoding UTF8
}
Write-Host "Exported $($functions.Count) Functions."

Write-Host "Fetching Views..."
$views = $db.Views | Where-Object { $_.Schema -in @('EJ', 'PTA', 'dbo') -and $_.IsSystemObject -eq $false }
$outDirViews = "C:\Dev\VsCode\EventJoy.Api\SQL\Views"
if (!(Test-Path $outDirViews)) { New-Item -ItemType Directory -Force -Path $outDirViews | Out-Null }

foreach ($v in $views) {
    $script = $scripter.EnumScript($v)
    $filePath = Join-Path $outDirViews "$($v.Schema).$($v.Name).sql"
    Set-Content -Path $filePath -Value ($script -join "`r`nGO`r`n") -Encoding UTF8
}
Write-Host "Exported $($views.Count) Views."

Write-Host "Done!"
