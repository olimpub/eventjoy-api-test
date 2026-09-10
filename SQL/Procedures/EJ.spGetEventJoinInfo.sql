CREATE OR ALTER PROCEDURE [EJ].[spGetEventJoinInfo]
    @EventUID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @EventID BIGINT, @Title NVARCHAR(200), @EventStatusID BIGINT, @EventStatusName NVARCHAR(100), @EventFlowID BIGINT;

    SELECT 
        @EventID = e.id, 
        @Title = e.Title,
        @EventStatusID = e.EventStatusID,
        @EventStatusName = s.StatusName,
        @EventFlowID = et.EventFlowID
    FROM [EJ].[tblEvent] e
    JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
    JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
    WHERE e.EventUID = @EventUID AND e.ActiveFlg = 1;

    IF @EventID IS NULL
    BEGIN
        SELECT 404 AS ReturnValue, N'Esemény nem található.' AS ReturnDescription;
        RETURN;
    END

    -- Check if CheckInOpen
    DECLARE @CheckInStepID INT;
    SELECT TOP 1 @CheckInStepID = StepID FROM [EJ].[tblEventFlowStatus] efs
    JOIN [EJ].[tblEventStatus] es ON efs.ToStatusID = es.id
    WHERE efs.EventFlowID = @EventFlowID AND (es.Code = 'checkin' OR es.StatusName LIKE N'%bejelentkez%');

    DECLARE @CurrentStepID INT;
    SELECT TOP 1 @CurrentStepID = StepID FROM [EJ].[tblEventFlowStatus] WHERE EventFlowID = @EventFlowID AND ToStatusID = @EventStatusID;

    DECLARE @CheckInOpen BIT = 0;
    IF @CurrentStepID >= @CheckInStepID
    BEGIN
        SET @CheckInOpen = 1;
    END

    SELECT 
        0 AS ReturnValue,
        'OK' AS ReturnDescription,
        @EventUID AS EventUID,
        @EventID AS EventID,
        @Title AS Title,
        @CheckInOpen AS CheckInOpen,
        @EventStatusName AS EventStatusName;
END
GO
