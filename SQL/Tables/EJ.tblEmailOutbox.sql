SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEmailOutbox](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[BatchID] [uniqueidentifier] NULL,
	[TemplateID] [int] NOT NULL,
	[RefID] [int] NULL,
	[UserID] [int] NOT NULL,
	[EmailName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[EmailAddress] [nvarchar](300) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[createdAt] [datetimeoffset](7) NOT NULL,
	[MailerSendID] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StatusID] [smallint] NULL,
	[processedAt] [datetimeoffset](7) NULL,
	[MailersendStatusID] [smallint] NULL,
	[deliveredAt] [datetimeoffset](7) NULL,
	[openedAt] [datetimeoffset](7) NULL,
	[clickedAt] [datetimeoffset](7) NULL
) ON [PRIMARY]

