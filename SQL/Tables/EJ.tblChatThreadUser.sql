SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblChatThreadUser](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[ChatThreadID] [bigint] NOT NULL,
	[UserID] [bigint] NOT NULL,
	[LastReadMessageID] [bigint] NULL,
	[LastDeliveredMessageID] [bigint] NULL,
	[JoinedAt] [datetimeoffset](0) NOT NULL,
	[IsMuted] [bit] NOT NULL
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblChatThreadUser] ADD  DEFAULT (sysdatetimeoffset()) FOR [JoinedAt]
GO
ALTER TABLE [EJ].[tblChatThreadUser] ADD  DEFAULT ((0)) FOR [IsMuted]
