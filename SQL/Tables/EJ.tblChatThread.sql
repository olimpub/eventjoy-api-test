SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblChatThread](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NULL,
	[ThreadTypeID] [bigint] NOT NULL,
	[Title] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblChatThread] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
CREATE NONCLUSTERED INDEX [IX_tblChatThread_ThreadTypeID] ON [EJ].[tblChatThread]
(
	[ThreadTypeID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblChatThread] ADD  CONSTRAINT [DF_tblChatThread_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblChatThread] ADD  CONSTRAINT [DF_tblChatThread_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblChatThread] ADD  CONSTRAINT [DF_tblChatThread_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
