SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PTA].[spRollbackEventRoundStatus]
    @EventRoundID INT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentHistoryID BIGINT;
    DECLARE @OldStatusID INT;
    DECLARE @NewStatusID INT;

    SELECT 
        @CurrentHistoryID = HistoryID,
        @OldStatusID = OldStatusID,
        @NewStatusID = NewStatusID
    FROM [PTA].[tblEventRoundStatusHistory]
    WHERE EventRoundID = @EventRoundID AND ActiveFlg = 1;

    IF @CurrentHistoryID IS NULL OR @OldStatusID IS NULL
    BEGIN
        SELECT 0 AS ReturnValue, 'Nincs visszavonható állapot.' AS ReturnDescription;
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM [PTA].[tblEventRoundStatusFlow]
        WHERE FromStatusID = @OldStatusID AND ToStatusID = @NewStatusID AND CanUndoFlg = 1
    )
    BEGIN
        SELECT 0 AS ReturnValue, 'Ez az állapotváltás nem visszavonható.' AS ReturnDescription;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN;

        UPDATE [PTA].[tblEventRoundStatusHistory]
        SET UndoFlg = 1, ActiveFlg = 0
        WHERE HistoryID = @CurrentHistoryID;

        DECLARE @PrevHistoryID BIGINT;
        SELECT TOP 1 @PrevHistoryID = HistoryID
        FROM [PTA].[tblEventRoundStatusHistory]
        WHERE EventRoundID = @EventRoundID AND HistoryID < @CurrentHistoryID AND UndoFlg = 0
        ORDER BY HistoryID DESC;

        IF @PrevHistoryID IS NOT NULL
        BEGIN
            UPDATE [PTA].[tblEventRoundStatusHistory]
            SET ActiveFlg = 1
            WHERE HistoryID = @PrevHistoryID;
        END

        UPDATE [PTA].[tblEventRound]
        SET EventRoundStatusID = @OldStatusID,
            LastUpdatedUserID = @UserID,
            updatedAt = SYSUTCDATETIME()
        WHERE EventRoundID = @EventRoundID;

        COMMIT TRAN;

        SELECT 1 AS ReturnValue, 'Sikeres visszavonás' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SELECT 0 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
