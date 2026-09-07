SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEmailTemplate](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[SourceID] [int] NOT NULL,
	[TemplateName] [nvarchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[MailerSendID] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[SenderMail] [varchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[MsgSubject] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ReplyToMail] [varchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ReplyToName] [varchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL
) ON [PRIMARY]

