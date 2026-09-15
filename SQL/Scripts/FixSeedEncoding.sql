SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

UPDATE [EJ].[tblAppVersionItem]
SET Description = N'Események létrehozása és jegyeladási rendszer implementálása.'
WHERE id = 1;

UPDATE [EJ].[tblAppVersionItem]
SET Description = N'Sysadmin portál és audit logolás integrálása.'
WHERE id = 2;

UPDATE [EJ].[tblAppVersionItem]
SET Description = N'Privát eseménytípusok (EventTypeOwner) bevezetése.'
WHERE id = 3;

UPDATE [EJ].[tblAppVersion]
SET Summary = N'Első nagy béta kiadás'
WHERE id = 1;

GO
