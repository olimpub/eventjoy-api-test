SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventRoundDesk](
	[EventRoundDeskID] [int] IDENTITY(1,1) NOT NULL,
	[EventRoundDeskUID] [uniqueidentifier] NOT NULL,
	[EventRoundID] [int] NOT NULL,
	[EventDeskID] [int] NOT NULL,
	[GameMasterUserID] [bigint] NULL,
	[CompletedAtUtc] [datetimeoffset](0) NULL,
	[AzurePhotoUrl] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[EventRoundDeskID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventRoundDesk] ADD  CONSTRAINT [DF_PTA_tblEventRoundDesk_UID]  DEFAULT (newid()) FOR [EventRoundDeskUID]
GO
ALTER TABLE [PTA].[tblEventRoundDesk] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblEventRoundDesk] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventRoundDesk] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
