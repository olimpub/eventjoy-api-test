SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventTypeGroup](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[GroupName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[OrderIndex] [int] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblEventTypeGroup] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblEventTypeGroup] ADD  DEFAULT ((0)) FOR [OrderIndex]
GO
ALTER TABLE [EJ].[tblEventTypeGroup] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventTypeGroup] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventTypeGroup] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
