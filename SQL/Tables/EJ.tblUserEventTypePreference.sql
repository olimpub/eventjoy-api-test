SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUserEventTypePreference](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[EventTypeID] [bigint] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblUserEventTypePreference] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblUserEventTypePreference_User_EventType] UNIQUE NONCLUSTERED 
(
	[UserID] ASC,
	[EventTypeID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblUserEventTypePreference] ADD  CONSTRAINT [DF_tblUserEventTypePreference_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblUserEventTypePreference] ADD  CONSTRAINT [DF_tblUserEventTypePreference_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
