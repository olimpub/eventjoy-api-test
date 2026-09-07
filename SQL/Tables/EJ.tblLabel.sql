SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblLabel](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[LabelName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Description] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL
) ON [PRIMARY]

