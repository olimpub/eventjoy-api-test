SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [LOG].[spGetSysadminDashboardMetrics]
    @Days INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartDate DATETIMEOFFSET = NULL;
    IF @Days IS NOT NULL
        SET @StartDate = DATEADD(day, -@Days, SYSDATETIMEOFFSET());

    SELECT 
        (SELECT COUNT(*) FROM [LOG].[tblErrorLog] WHERE (@StartDate IS NULL OR createdAt >= @StartDate)) AS ErrorLogCount,
        (SELECT COUNT(*) FROM [LOG].[tblDataChangeLog] WHERE (@StartDate IS NULL OR CreatedAt >= @StartDate)) AS DataChangeLogCount,
        (SELECT COUNT(*) FROM [EJ].[tblTicket] WHERE StatusID = 1 AND (@StartDate IS NULL OR createdAt >= @StartDate)) AS OpenTicketsCount,
        (SELECT COUNT(*) FROM [EJ].[tblTicket] WHERE StatusID = 2 AND (@StartDate IS NULL OR createdAt >= @StartDate)) AS InProgressTicketsCount,
        (SELECT COUNT(*) FROM [EJ].[tblEvent] WHERE (@StartDate IS NULL OR createdAt >= @StartDate)) AS NewEventsCount,
        (SELECT COUNT(*) FROM [EJ].[tblEvent]) AS TotalActiveEventsCount,
        (SELECT COUNT(*) FROM [EJ].[tblUser] WHERE (@StartDate IS NULL OR createdAt >= @StartDate)) AS NewUsersCount,
        (SELECT COUNT(*) FROM [EJ].[tblUser]) AS TotalUsersCount,
        (SELECT COUNT(*) FROM [EJ].[tblEmailOutbox] WHERE StatusID = 1 AND (@StartDate IS NULL OR createdAt >= @StartDate)) AS EmailsSentSuccessfully,
        (SELECT COUNT(*) FROM [EJ].[tblEmailOutbox] WHERE StatusID = -1 AND (@StartDate IS NULL OR createdAt >= @StartDate)) AS EmailsFailed
END

