-- ==============================================================================================
-- [EJ].[tblCommunicationOutbox]
-- Felelősség: Tranzakcionális outbox tábla az összes kimenő kommunikációnak (Email, SMS, Push, stb.)
-- ==============================================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblCommunicationOutbox]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblCommunicationOutbox](
        [CommunicationOutboxID] [bigint] IDENTITY(1,1) NOT NULL,
        [Channel] [nvarchar](50) NOT NULL,            -- pl. 'email', 'sms', 'signalr', 'push'
        [MessageType] [nvarchar](100) NOT NULL,       -- pl. 'Otp', 'EventInvite', 'ChatMessage'
        [RecipientInfo] [nvarchar](255) NULL,         -- pl. email cím, telefonszám, vagy UserID
        [TemplateID] [nvarchar](100) NULL,            -- Provider specifikus template ID (pl. MailerSend template)
        [TemplateDataJson] [nvarchar](max) NULL,      -- JSON formátumú adatok a template-hez
        [Status] [nvarchar](50) NOT NULL,             -- 'Pending', 'Queued', 'Submitted', 'Delivered', 'Failed', 'Bounced'
        [ProviderMessageID] [nvarchar](255) NULL,     -- pl. x-message-id a MailerSendtől a státusz frissítéshez
        [CreatedAt] [datetimeoffset](0) NOT NULL DEFAULT (SYSDATETIMEOFFSET()),
        [UpdatedAt] [datetimeoffset](0) NOT NULL DEFAULT (SYSDATETIMEOFFSET()),
        CONSTRAINT [PK_tblCommunicationOutbox] PRIMARY KEY CLUSTERED 
        (
            [CommunicationOutboxID] ASC
        )
    ) ON [PRIMARY]
END
GO
