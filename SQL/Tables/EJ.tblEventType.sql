SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventType](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventTypeGroupID] [bigint] NOT NULL,
	[Code] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[TypeName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Description] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PublicFlg] [bit] NOT NULL,
	[IconName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[CanEnterFlg] [bit] NOT NULL,
	[EventFlowID] [bigint] NULL,
	[PTAFlg] [bit] NULL,
 CONSTRAINT [PK_tblEventType] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblEventType] ADD  DEFAULT ((1)) FOR [PublicFlg]
GO
ALTER TABLE [EJ].[tblEventType] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventType] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventType] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
GO
ALTER TABLE [EJ].[tblEventType] ADD  DEFAULT ((0)) FOR [CanEnterFlg]
