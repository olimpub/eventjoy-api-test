SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

UPDATE [EJ].[tblAppVersion] 
SET Summary = N'Árvíztűrő tükörfúrógép'
WHERE id = 1;

UPDATE [EJ].[tblAppVersionItem]
SET Description = N'Árvíztűrő tükörfúrógép - Teszt'
WHERE id = 1;
GO
