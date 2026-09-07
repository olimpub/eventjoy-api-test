SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEvent](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventUID] [uniqueidentifier] NOT NULL,
	[EventTypeID] [bigint] NOT NULL,
	[EventStatusID] [bigint] NOT NULL,
	[EventLocationID] [bigint] NULL,
	[Title] [nvarchar](300) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Description] [nvarchar](max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StartAtUtc] [datetimeoffset](0) NOT NULL,
	[EndAtUtc] [datetimeoffset](0) NULL,
	[CreatedByUserID] [bigint] NOT NULL,
	[Capacity] [int] NULL,
	[OnlineFlg] [bit] NOT NULL,
	[PublicFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[OnlineURL] [varchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PendingApprovalID] [bigint] NULL,
	[PrevEventStatusID] [bigint] NULL,
	[EventImageUrl] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ContactOrganizerID] [bigint] NULL,
	[ContactName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ContactEmail] [nvarchar](320) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ContactPhone] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
 CONSTRAINT [PK_tblEvent] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT (newid()) FOR [EventUID]
GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT ((0)) FOR [OnlineFlg]
GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT ((1)) FOR [PublicFlg]
GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEvent] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
