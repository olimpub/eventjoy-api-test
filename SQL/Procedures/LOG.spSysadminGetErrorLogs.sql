SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [LOG].[spSysadminGetErrorLogs]
    @From DATETIME2,
    @To DATETIME2,
    @Source NVARCHAR(50) = NULL,
    @SearchTerm NVARCHAR(MAX) = NULL,
    @UserID INT = NULL,
    @Skip INT,
    @Take INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ErrorID,
        e.UserID,
        LTRIM(RTRIM(ISNULL(u.LastName, '') + ' ' + ISNULL(u.FirstName, ''))) AS UserName,
        e.Source,
        e.Severity,
        e.UrlOrAction,
        e.ErrorMessage,
        e.StackTrace,
        e.ContextPayload_JSON,
        e.CreatedAt
    FROM [LOG].[tblErrorLog] e
    LEFT JOIN [EJ].[tblUser] u ON e.UserID = u.Id
    WHERE 
        e.CreatedAt >= @From 
        AND e.CreatedAt <= @To
        AND (
            @Source IS NULL
            OR (@Source = 'Frontend' AND e.Source = 'Frontend')
            OR (@Source = 'Backend' AND e.Source IN ('Backend', 'API'))
            OR (@Source NOT IN ('Frontend', 'Backend') AND e.Source = @Source)
        )
        AND (@SearchTerm IS NULL OR e.ErrorMessage LIKE '%' + @SearchTerm + '%')
        AND (@UserID IS NULL OR e.UserID = @UserID)
    ORDER BY e.CreatedAt DESC, e.ErrorID DESC
    OFFSET @Skip ROWS
    FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) 
    FROM [LOG].[tblErrorLog] e
    WHERE 
        e.CreatedAt >= @From 
        AND e.CreatedAt <= @To
        AND (
            @Source IS NULL
            OR (@Source = 'Frontend' AND e.Source = 'Frontend')
            OR (@Source = 'Backend' AND e.Source IN ('Backend', 'API'))
            OR (@Source NOT IN ('Frontend', 'Backend') AND e.Source = @Source)
        )
        AND (@SearchTerm IS NULL OR e.ErrorMessage LIKE '%' + @SearchTerm + '%')
        AND (@UserID IS NULL OR e.UserID = @UserID);
END
