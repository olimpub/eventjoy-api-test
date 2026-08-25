-- ==============================================================================================
-- [EJ].[spGetCommunicationForDelivery]
-- Felelősség: Kiolvassa az outbox rekordot a Service Bus trigger alapján.
-- ==============================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spGetCommunicationForDelivery]
    @CommunicationOutboxID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        [CommunicationOutboxID],
        [Channel],
        [MessageType],
        [RecipientInfo],
        [TemplateID],
        [TemplateDataJson],
        [Status]
    FROM [EJ].[tblCommunicationOutbox]
    WHERE [CommunicationOutboxID] = @CommunicationOutboxID;
END
GO
