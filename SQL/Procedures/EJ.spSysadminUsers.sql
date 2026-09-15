SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetUsers]
    @SearchTerm NVARCHAR(100) = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id, EmailAddress, FirstName, LastName, StatusID, IsSysadmin, createdAt, updatedAt
    FROM [EJ].[tblUser]
    WHERE 
        (@SearchTerm IS NULL 
         OR EmailAddress LIKE '%' + @SearchTerm + '%'
         OR FirstName LIKE '%' + @SearchTerm + '%'
         OR LastName LIKE '%' + @SearchTerm + '%')
    ORDER BY createdAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    -- Total Count
    SELECT COUNT(*) AS TotalCount
    FROM [EJ].[tblUser]
    WHERE 
        (@SearchTerm IS NULL 
         OR EmailAddress LIKE '%' + @SearchTerm + '%'
         OR FirstName LIKE '%' + @SearchTerm + '%'
         OR LastName LIKE '%' + @SearchTerm + '%');
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminUpdateUser]
    @TargetUserID BIGINT,
    @FirstName NVARCHAR(150),
    @LastName NVARCHAR(150),
    @StatusID INT,
    @IsSysadmin BIT,
    @SysadminUserID BIGINT -- Ki módosította
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE [EJ].[tblUser]
        SET 
            FirstName = @FirstName,
            LastName = @LastName,
            StatusID = @StatusID,
            IsSysadmin = @IsSysadmin,
            LastUpdatedUserID = @SysadminUserID,
            updatedAt = SYSDATETIMEOFFSET()
        WHERE Id = @TargetUserID;
        
        SELECT 1 AS ReturnValue, N'Sikeres módosítás.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminForceLogoutUser]
    @TargetUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM [EJ].[tblRefreshToken] WHERE UserId = @TargetUserID;
        SELECT 1 AS ReturnValue, N'Kijelentkeztetés sikeres.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO

