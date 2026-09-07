SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblChatMessage](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[ChatThreadID] [bigint] NOT NULL,
	[SenderUserID] [bigint] NOT NULL,
	[MessageText] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AttachmentUrl] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IsSystemMessage] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblChatMessage] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
CREATE NONCLUSTERED INDEX [IX_tblChatMessage_Thread_Created] ON [EJ].[tblChatMessage]
(
	[ChatThreadID] ASC,
	[createdAt] DESC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblChatMessage] ADD  DEFAULT ((0)) FOR [IsSystemMessage]
GO
ALTER TABLE [EJ].[tblChatMessage] ADD  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [EJ].[tblChatMessage] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblChatMessage] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
