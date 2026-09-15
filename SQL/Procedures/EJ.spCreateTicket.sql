SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [EJ].[spCreateTicket]
    @ReporterUserID BIGINT,
    @Title NVARCHAR(255),
    @Description NVARCHAR(MAX),
    @TicketTypeID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [EJ].[tblTicketType] WHERE TicketTypeID = @TicketTypeID AND ActiveFlg = 1)
    BEGIN
        SELECT 0 AS ReturnValue, 'Érvénytelen Ticket Típus' AS ReturnDescription;
        RETURN;
    END

    BEGIN TRY
        DECLARE @NewTicketID BIGINT;

        INSERT INTO [EJ].[tblTicket] (ReporterUserID, Title, Description, TicketTypeID, StatusID, LastUpdatedUserID, createdAt, updatedAt)
        VALUES (@ReporterUserID, @Title, @Description, @TicketTypeID, 1, @ReporterUserID, SYSUTCDATETIME(), SYSUTCDATETIME());

        SET @NewTicketID = SCOPE_IDENTITY();

        SELECT 1 AS ReturnValue, 'Sikeres rögzítés' AS ReturnDescription, @NewTicketID AS TicketID;
    END TRY
    BEGIN CATCH
        SELECT 0 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
