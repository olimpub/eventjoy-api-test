SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblGameType](
	[GameTypeID] [int] IDENTITY(1,1) NOT NULL,
	[GName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[GameTypeID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_PTA_tblGameType_Name] UNIQUE NONCLUSTERED 
(
	[GName] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblGameType] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblGameType] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblGameType] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
