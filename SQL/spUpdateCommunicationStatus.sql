-- ==============================================================================================
-- [EJ].[spUpdateCommunicationStatus]
-- Felelősség: Frissíti az outbox rekord állapotát kiküldés vagy hiba után.
-- ==============================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spUpdateCommunicationStatus]
    @CommunicationOutboxID BIGINT,
    @Status NVARCHAR(50),
    @ProviderMessageID NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE [EJ].[tblCommunicationOutbox]
    SET 
        [Status] = @Status,
        [ProviderMessageID] = ISNULL(@ProviderMessageID, [ProviderMessageID]),
        [UpdatedAt] = SYSDATETIMEOFFSET()
    WHERE [CommunicationOutboxID] = @CommunicationOutboxID;
END
GO
