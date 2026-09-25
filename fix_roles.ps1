$file = "C:\Dev\VsCode\EventJoy.Api\OlimpubMediaEndpoints.cs"
$content = Get-Content $file -Raw
$content = $content -replace "EventRoleID = 432", "eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.Code IN ('organizer', 'Owner', 'host') AND eu.ActiveFlg = 1"
$content = $content -replace "FROM \[EJ\]\.\[tblEventUser\] WHERE EventID", "FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er"
$content = $content -replace "EventRoleID = 435", "eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.Code = 'game_master' AND eu.ActiveFlg = 1"

Set-Content $file $content
