SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [LOG].[spSysadminGetErrorLogs]
    @SearchTerm NVARCHAR(200) = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT *
    FROM [LOG].[tblErrorLog]
    WHERE 
        (@SearchTerm IS NULL 
         OR ErrorMessage LIKE '%' + @SearchTerm + '%'
         OR StackTrace LIKE '%' + @SearchTerm + '%'
         OR Component LIKE '%' + @SearchTerm + '%')
    ORDER BY createdAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM [LOG].[tblErrorLog]
    WHERE 
        (@SearchTerm IS NULL 
         OR ErrorMessage LIKE '%' + @SearchTerm + '%'
         OR StackTrace LIKE '%' + @SearchTerm + '%'
         OR Component LIKE '%' + @SearchTerm + '%');
END
GO

CREATE OR ALTER PROCEDURE [LOG].[spSysadminGetDataChangeLogs]
    @TableName NVARCHAR(100) = NULL,
    @UserID BIGINT = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT *
    FROM [LOG].[tblDataChangeLog]
    WHERE 
        (@TableName IS NULL OR TableName = @TableName)
        AND (@UserID IS NULL OR UserID = @UserID)
    ORDER BY CreatedAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM [LOG].[tblDataChangeLog]
    WHERE 
        (@TableName IS NULL OR TableName = @TableName)
        AND (@UserID IS NULL OR UserID = @UserID);
END
GO

