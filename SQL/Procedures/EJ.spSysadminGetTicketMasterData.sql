SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetTicketMasterData]
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 1. Statuses
    SELECT TicketStatusID, StatusName, IsClosedState
    FROM [EJ].[tblTicketStatus]
    WHERE ActiveFlg = 1;

    -- 2. Status Flows
    SELECT FromStatusID, ToStatusID
    FROM [EJ].[tblTicketStatusFlow]
    WHERE ActiveFlg = 1;
END
