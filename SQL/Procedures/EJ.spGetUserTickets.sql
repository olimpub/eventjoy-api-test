SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [EJ].[spGetUserTickets]
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 1 AS ReturnValue, 'Success' AS ReturnDescription;
    SELECT 'Tickets' AS ResultName;

    SELECT 
        t.TicketID,
        t.Title,
        t.TicketTypeID,
        ty.TypeName,
        t.StatusID,
        s.StatusName,
        s.IsClosedState,
        t.updatedAt,
        t.createdAt
    FROM [EJ].[tblTicket] t
    JOIN [EJ].[tblTicketType] ty ON t.TicketTypeID = ty.TicketTypeID
    JOIN [EJ].[tblTicketStatus] s ON t.StatusID = s.TicketStatusID
    WHERE t.ReporterUserID = @UserID
    ORDER BY t.updatedAt DESC;
END
GO
