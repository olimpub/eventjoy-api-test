SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [EJ].[spGetTicketMetadata]
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 1 AS ReturnValue, 'Success' AS ReturnDescription;

    SELECT 'TicketTypes' AS ResultName;
    SELECT TicketTypeID, TypeName 
    FROM [EJ].[tblTicketType] 
    WHERE ActiveFlg = 1;

    SELECT 'TicketStatuses' AS ResultName;
    SELECT TicketStatusID, StatusName, IsClosedState 
    FROM [EJ].[tblTicketStatus] 
    WHERE ActiveFlg = 1;
END
GO
