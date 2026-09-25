$connString = "Server=tcp:pulsator-prod.database.windows.net,1433;Initial Catalog=eventjoy-test;Persist Security Info=False;User ID=pulsator_root;Password=8sHFdrCp7u;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT OBJECT_DEFINITION(OBJECT_ID('[OP].[spSaveQuestion]'))"
$sql = $cmd.ExecuteScalar()

$sql = $sql -replace '(?i)CREATE\s+PROCEDURE', 'CREATE OR ALTER PROCEDURE'

$replaceTarget = "(?s)-- 2\. Update tblQuestion.*?WHERE id = @QuestionID;"
$replacement = @"
-- 2. Update tblQuestion
        UPDATE [OP].[tblQuestion]
        SET Prompt = @NewPrompt,
            TimeSec = @NewTimeSec,
            LastCreatedUserID = @UserID
        WHERE id = @QuestionID;
        
        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'ImageKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET ImageKey = JSON_VALUE(@Json, '$.ImageKey') WHERE id = @QuestionID;
        END

        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'AudioKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET AudioKey = JSON_VALUE(@Json, '$.AudioKey') WHERE id = @QuestionID;
        END
"@

$sql = $sql -replace $replaceTarget, $replacement

$cmd.CommandText = "SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;"
$cmd.ExecuteNonQuery()

$cmd.CommandText = $sql
$cmd.ExecuteNonQuery()
$conn.Close()
Write-Host "Success!"
