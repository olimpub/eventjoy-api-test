SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PTA].[spUpdateEventRoundStatus]
    @EventRoundID INT,
    @NewStatusID INT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentStatusID INT;

    SELECT @CurrentStatusID = EventRoundStatusID 
    FROM [PTA].[tblEventRound]
    WHERE EventRoundID = @EventRoundID;

    IF @CurrentStatusID IS NULL
    BEGIN
        SELECT 0 AS ReturnValue, 'Érvénytelen EventRoundID' AS ReturnDescription;
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 
        FROM [PTA].[tblEventRoundStatusFlow] 
        WHERE FromStatusID = @CurrentStatusID AND ToStatusID = @NewStatusID AND ActiveFlg = 1
    )
    BEGIN
        SELECT 0 AS ReturnValue, 'Érvénytelen vagy nem engedélyezett státuszváltás.' AS ReturnDescription;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        UPDATE [PTA].[tblEventRoundStatusHistory]
        SET ActiveFlg = 0
        WHERE EventRoundID = @EventRoundID AND ActiveFlg = 1;

        INSERT INTO [PTA].[tblEventRoundStatusHistory] 
        (EventRoundID, OldStatusID, NewStatusID, ActiveFlg, UndoFlg, ChangedByUserID, ChangeDate)
        VALUES 
        (@EventRoundID, @CurrentStatusID, @NewStatusID, 1, 0, @UserID, SYSUTCDATETIME());

        UPDATE [PTA].[tblEventRound]
        SET EventRoundStatusID = @NewStatusID,
            LastUpdatedUserID = @UserID,
            updatedAt = SYSUTCDATETIME()
        WHERE EventRoundID = @EventRoundID;

        COMMIT TRAN;

        SELECT 1 AS ReturnValue, 'Sikeres módosítás' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SELECT 0 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
