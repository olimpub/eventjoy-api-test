SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [EJ].[spWithdrawTicket]
    @TicketID BIGINT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStatusID INT;

    SELECT @CurrentStatusID = StatusID
    FROM [EJ].[tblTicket]
    WHERE TicketID = @TicketID AND ReporterUserID = @UserID;

    IF @CurrentStatusID IS NULL
    BEGIN
        SELECT 0 AS ReturnValue, 'Nincs jogosultság vagy érvénytelen jegy.' AS ReturnDescription;
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM [EJ].[tblTicketStatusFlow]
        WHERE FromStatusID = @CurrentStatusID AND ToStatusID = 6 AND ActiveFlg = 1
    )
    BEGIN
        SELECT 0 AS ReturnValue, 'Jelenlegi állapotból a jegy már nem vonható vissza.' AS ReturnDescription;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        UPDATE [EJ].[tblTicket]
        SET StatusID = 6, updatedAt = SYSUTCDATETIME(), LastUpdatedUserID = @UserID
        WHERE TicketID = @TicketID;

        INSERT INTO [EJ].[tblTicketComment] (TicketID, UserID, CommentText, IsSystemMessage, LastUpdatedUserID, createdAt, updatedAt)
        VALUES (@TicketID, @UserID, 'A felhasználó visszavonta az igényt/hibajegyet.', 1, @UserID, SYSUTCDATETIME(), SYSUTCDATETIME());

        COMMIT TRAN;

        SELECT 1 AS ReturnValue, 'Jegy visszavonva' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SELECT 0 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
