-- ==============================================================================================
-- [EJ].[spGetPendingOutboxMessages]
-- Felelősség: Kikeresi és lefoglalja a kiküldésre váró rekordokat (Pending -> Queued)
-- ==============================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spGetPendingOutboxMessages]
    @BatchSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    -- A rekordokat egyszerre lockoljuk és módosítjuk, hogy több párhuzamos dispatcher se akadjon össze
    UPDATE TOP (@BatchSize) [EJ].[tblCommunicationOutbox]
    SET 
        [Status] = 'Queued',
        [UpdatedAt] = SYSDATETIMEOFFSET()
    OUTPUT 
        inserted.CommunicationOutboxID,
        inserted.Channel
    WHERE [Status] = 'Pending';
END
GO
