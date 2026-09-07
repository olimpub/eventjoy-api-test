SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventStatus](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Code] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[StatusName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ColorCode] [varchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[ClosedFlg] [bit] NOT NULL,
	[InProgressFlg] [bit] NOT NULL
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblEventStatus] ADD  DEFAULT ((0)) FOR [ClosedFlg]
GO
ALTER TABLE [EJ].[tblEventStatus] ADD  DEFAULT ((0)) FOR [InProgressFlg]
