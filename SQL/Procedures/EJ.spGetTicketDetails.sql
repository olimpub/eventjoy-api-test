SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [EJ].[spGetTicketDetails]
    @TicketID BIGINT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (SELECT 1 FROM [EJ].[tblTicket] WHERE TicketID = @TicketID AND ReporterUserID = @UserID)
    BEGIN
        SELECT 0 AS ReturnValue, 'Nincs jogosultság vagy érvénytelen jegy.' AS ReturnDescription;
        RETURN;
    END

    SELECT 1 AS ReturnValue, 'Success' AS ReturnDescription;

    SELECT 'TicketDetails' AS ResultName;
    SELECT 
        t.TicketID,
        t.Title,
        t.Description,
        t.TicketTypeID,
        ty.TypeName,
        t.StatusID,
        s.StatusName,
        s.IsClosedState,
        t.TargetVersion,
        t.createdAt,
        t.updatedAt
    FROM [EJ].[tblTicket] t
    JOIN [EJ].[tblTicketType] ty ON t.TicketTypeID = ty.TicketTypeID
    JOIN [EJ].[tblTicketStatus] s ON t.StatusID = s.TicketStatusID
    WHERE t.TicketID = @TicketID;

    SELECT 'TicketComments' AS ResultName;
    SELECT 
        c.CommentID,
        c.UserID,
        CASE 
            WHEN c.IsSystemMessage = 1 THEN 'Rendszerüzenet'
            WHEN c.UserID = t.ReporterUserID THEN 'Saját'
            ELSE 'Sysadmin / AI' 
        END AS SenderType,
        c.CommentText,
        c.IsSystemMessage,
        c.createdAt
    FROM [EJ].[tblTicketComment] c
    JOIN [EJ].[tblTicket] t ON c.TicketID = t.TicketID
    WHERE c.TicketID = @TicketID
    ORDER BY c.createdAt ASC;
END
GO
