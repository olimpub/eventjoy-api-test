SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUserSettings](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[NotifyNewMessage] [bit] NOT NULL,
	[NotifyUpcomingEvent] [bit] NOT NULL,
	[NotifyCommunityNews] [bit] NOT NULL,
	[NotifyPaymentReminder] [bit] NOT NULL,
	[AllowEmailNotifications] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblUserSettings] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblUserSettings_UserID] UNIQUE NONCLUSTERED 
(
	[UserID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_NotifyNewMessage]  DEFAULT ((1)) FOR [NotifyNewMessage]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_NotifyUpcomingEvent]  DEFAULT ((1)) FOR [NotifyUpcomingEvent]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_NotifyCommunityNews]  DEFAULT ((1)) FOR [NotifyCommunityNews]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_NotifyPaymentReminder]  DEFAULT ((1)) FOR [NotifyPaymentReminder]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_AllowEmailNotifications]  DEFAULT ((1)) FOR [AllowEmailNotifications]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblUserSettings] ADD  CONSTRAINT [DF_tblUserSettings_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
