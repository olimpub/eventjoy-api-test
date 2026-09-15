SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetTickets]
    @StatusID INT = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        t.*,
        u.EmailAddress AS ReporterEmail,
        u.FirstName AS ReporterFirstName,
        u.LastName AS ReporterLastName
    FROM [EJ].[tblTicket] t
    LEFT JOIN [EJ].[tblUser] u ON t.ReporterUserID = u.Id
    WHERE 
        (@StatusID IS NULL OR t.StatusID = @StatusID)
    ORDER BY t.createdAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM [EJ].[tblTicket]
    WHERE 
        (@StatusID IS NULL OR StatusID = @StatusID);
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminUpdateTicketStatus]
    @TicketID BIGINT,
    @StatusID INT,
    @SysadminUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE [EJ].[tblTicket]
        SET 
            StatusID = @StatusID,
            LastUpdatedUserID = @SysadminUserID,
            updatedAt = SYSDATETIMEOFFSET()
        WHERE TicketID = @TicketID;
        
        SELECT 1 AS ReturnValue, N'Sikeres módosítás.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO

