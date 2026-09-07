SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblPairMode](
	[PairModeID] [int] IDENTITY(1,1) NOT NULL,
	[PName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[PDesc] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[PairGameFlg] [bit] NOT NULL,
	[FixedGroupFlg] [bit] NOT NULL,
	[SameGroupFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[PairModeID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblPairMode] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblPairMode] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblPairMode] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
