SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [PTA].[spGetEventRoundAvailableStatuses]
    @EventRoundID INT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentStatusID INT;
    DECLARE @CanUndoCurrent BIT = 0;

    SELECT @CurrentStatusID = EventRoundStatusID 
    FROM [PTA].[tblEventRound]
    WHERE EventRoundID = @EventRoundID;

    IF @CurrentStatusID IS NULL
    BEGIN
        SELECT 0 AS ReturnValue, 'Érvénytelen EventRoundID' AS ReturnDescription;
        RETURN;
    END

    IF EXISTS (
        SELECT 1 
        FROM [PTA].[tblEventRoundStatusHistory] h
        JOIN [PTA].[tblEventRoundStatusFlow] f ON h.OldStatusID = f.FromStatusID AND h.NewStatusID = f.ToStatusID
        WHERE h.EventRoundID = @EventRoundID AND h.ActiveFlg = 1 AND f.CanUndoFlg = 1
    )
    BEGIN
        SET @CanUndoCurrent = 1;
    END

    SELECT 
        1 AS ReturnValue, 
        'Success' AS ReturnDescription,
        @CurrentStatusID AS CurrentStatusID,
        @CanUndoCurrent AS CanUndoCurrent;

    SELECT 'AvailableStatuses' AS ResultName;

    SELECT 
        f.ToStatusID AS StatusID,
        s.SName AS StatusName
    FROM [PTA].[tblEventRoundStatusFlow] f
    JOIN [PTA].[tblEventRoundStatus] s ON f.ToStatusID = s.EventRoundStatusID
    WHERE f.FromStatusID = @CurrentStatusID AND f.ActiveFlg = 1 AND s.ActiveFlg = 1;

END
GO
