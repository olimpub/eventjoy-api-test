SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [LOG].[spSysadminGetDictionaries]
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT * FROM [LOG].[tblAuditTableDictionary];
    SELECT * FROM [LOG].[tblAuditFieldDictionary];
END
GO

