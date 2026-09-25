$connString = "Server=tcp:pulsator-prod.database.windows.net,1433;Initial Catalog=eventjoy-test;Persist Security Info=False;User ID=pulsator_root;Password=8sHFdrCp7u;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT OBJECT_DEFINITION(OBJECT_ID('[OP].[spGetEventData]'))"
$sql = $cmd.ExecuteScalar()

$sql = $sql -replace '(?i)CREATE\s+PROCEDURE', 'CREATE OR ALTER PROCEDURE'

$replaceTarget = "(?s)eq\.StartedAtUtc, eq\.TimeSec,.*?q\.Prompt, q\.MediaUrl, qt\.Code AS TypeCode,"
$replacement = @"
eq.StartedAtUtc, eq.TimeSec,
        q.Prompt, q.MediaUrl, q.ImageKey, q.AudioKey, qt.Code AS TypeCode,
"@

$sql = $sql -replace $replaceTarget, $replacement

$cmd.CommandText = "SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;"
$cmd.ExecuteNonQuery()

$cmd.CommandText = $sql
$cmd.ExecuteNonQuery()
$conn.Close()
Write-Host "Success!"
