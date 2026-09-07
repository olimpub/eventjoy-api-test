SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventPlayer](
	[EventPlayerID] [int] IDENTITY(1,1) NOT NULL,
	[EventID] [int] NOT NULL,
	[EventUserID] [bigint] NOT NULL,
	[NickName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[OrganizationName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TeamName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CompanyName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[RegionName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[FinalPoint] [decimal](18, 2) NULL,
	[FinalPosition] [int] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[FinalTruckPoint] [decimal](18, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[EventPlayerID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventPlayer] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblEventPlayer] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventPlayer] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
