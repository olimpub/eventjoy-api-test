SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblSMSOutbox](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[SenderType] [varchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[SenderName] [varchar](15) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[RefID] [int] NULL,
	[UserID] [int] NOT NULL,
	[PhoneNo] [varchar](30) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Message] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[createdAt] [datetimeoffset](7) NOT NULL,
	[ProviderID] [varchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StatusID] [smallint] NULL,
	[processedAt] [datetimeoffset](7) NULL,
	[ProviderStatusID] [smallint] NULL,
	[deliveredAt] [datetimeoffset](7) NULL,
	[bufferedAt] [datetimeoffset](7) NULL
) ON [PRIMARY]

