SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblNotification](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[EventID] [bigint] NULL,
	[NotificationTypeID] [bigint] NOT NULL,
	[Title] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[MessageBody] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActionUrl] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IsRead] [bit] NOT NULL,
	[ReadAtUtc] [datetimeoffset](0) NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblNotification] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
CREATE NONCLUSTERED INDEX [IX_tblNotification_NotificationType] ON [EJ].[tblNotification]
(
	[NotificationTypeID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_tblNotification_User_Unread] ON [EJ].[tblNotification]
(
	[UserID] ASC,
	[IsRead] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblNotification] ADD  CONSTRAINT [DF_tblNotification_IsRead]  DEFAULT ((0)) FOR [IsRead]
GO
ALTER TABLE [EJ].[tblNotification] ADD  CONSTRAINT [DF_tblNotification_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblNotification] ADD  CONSTRAINT [DF_tblNotification_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
