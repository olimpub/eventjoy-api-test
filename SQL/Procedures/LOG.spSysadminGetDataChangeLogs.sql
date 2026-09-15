SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [LOG].[spSysadminGetDataChangeLogs]
    @From DATETIME2,
    @To DATETIME2,
    @TableName NVARCHAR(255) = NULL,
    @UserID INT = NULL,
    @Skip INT,
    @Take INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        l.LogID,
        l.TableName,
        NULL AS RecordID,
        l.ActionType,
        l.OldData_JSON,
        l.NewData_JSON,
        l.UserID,
        LTRIM(RTRIM(ISNULL(u.LastName, '') + ' ' + ISNULL(u.FirstName, ''))) AS UserName,
        l.CreatedAt
    FROM [LOG].[tblDataChangeLog] l
    LEFT JOIN [EJ].[tblUser] u ON l.UserID = u.Id
    WHERE 
        l.CreatedAt >= @From 
        AND l.CreatedAt <= @To
        AND (@TableName IS NULL OR l.TableName = @TableName)
        AND (@UserID IS NULL OR l.UserID = @UserID)
    ORDER BY l.CreatedAt DESC, l.LogID DESC
    OFFSET @Skip ROWS
    FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) 
    FROM [LOG].[tblDataChangeLog] l
    WHERE 
        l.CreatedAt >= @From 
        AND l.CreatedAt <= @To
        AND (@TableName IS NULL OR l.TableName = @TableName)
        AND (@UserID IS NULL OR l.UserID = @UserID);
END
