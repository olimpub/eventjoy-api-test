$filePath = "SQL/Procedures/EJ.spImportInvitations.sql"
$content = Get-Content $filePath -Encoding UTF8 -Raw

$newValidation = @"
        UPDATE i
        SET ResultMsg = CONCAT(ISNULL(i.ResultMsg + '; ', ''), N'Már résztvevő')
        FROM #Invitations i
        INNER JOIN [EJ].[tblUser] u ON LOWER(LTRIM(RTRIM(i.Email))) = LOWER(LTRIM(RTRIM(u.Email)))
        INNER JOIN [EJ].[tblEventUser] eu ON eu.UserID = u.id AND eu.EventID = @EventID;

        -- 6. Hiba riportolás
"@

$content = $content.Replace("        -- 6. Hiba riportolás", $newValidation)

Set-Content $filePath $content -Encoding UTF8
Write-Host "Done"
