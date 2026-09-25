$filePath = "SQL/Procedures/EJ.spChangeEvent.sql"
$content = Get-Content $filePath -Encoding UTF8 -Raw
$old = "                INNER JOIN [EJ].[tblEventRoleTicket] ert ON eu.EventTicketID = ert.EventTicketID `r`n                INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id"
$old2 = "                INNER JOIN [EJ].[tblEventRoleTicket] ert ON eu.EventTicketID = ert.EventTicketID `n                INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id"
$new = "                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id"
$content = $content.Replace($old, $new).Replace($old2, $new)

Set-Content $filePath $content -Encoding UTF8
Write-Host "Done"
