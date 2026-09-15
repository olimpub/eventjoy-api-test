SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [EJ].[spAddTicketComment]
    @TicketID BIGINT,
    @UserID BIGINT,
    @CommentText NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [EJ].[tblTicket] WHERE TicketID = @TicketID AND ReporterUserID = @UserID)
    BEGIN
        SELECT 0 AS ReturnValue, 'Nincs jogosultság vagy érvénytelen jegy.' AS ReturnDescription;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        INSERT INTO [EJ].[tblTicketComment] (TicketID, UserID, CommentText, IsSystemMessage, LastUpdatedUserID, createdAt, updatedAt)
        VALUES (@TicketID, @UserID, @CommentText, 0, @UserID, SYSUTCDATETIME(), SYSUTCDATETIME());

        UPDATE [EJ].[tblTicket]
        SET updatedAt = SYSUTCDATETIME(), LastUpdatedUserID = @UserID
        WHERE TicketID = @TicketID;

        COMMIT TRAN;

        SELECT 1 AS ReturnValue, 'Komment hozzáadva' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SELECT 0 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
