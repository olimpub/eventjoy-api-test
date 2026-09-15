SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetImpersonationData]
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id AS Id, EmailAddress 
    FROM [EJ].[tblUser] 
    WHERE id = @UserID;
END
