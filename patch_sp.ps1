$filePath = "SQL/Procedures/EJ.spChangeEvent.sql"
$content = Get-Content $filePath -Raw
$old = "                INNER JOIN [EJ].[tblEventRoleTicket] ert ON eu.EventTicketID = ert.EventTicketID `n                INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id"
$new = "                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id"
$content = $content.Replace($old, $new)

$old2 = "                INNER JOIN [EJ].[tblEventRoleTicket] ert ON eu.EventTicketID = ert.EventTicketID `r`n                INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id"
$content = $content.Replace($old2, $new)

Set-Content $filePath $content
Write-Host "Done"
