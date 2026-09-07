SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblChampionships](
	[ChampionshipID] [int] IDENTITY(1,1) NOT NULL,
	[CName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[CDescription] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[FromDate] [date] NOT NULL,
	[ToDate] [date] NOT NULL,
	[MultiLocatonFlg] [bit] NOT NULL,
	[LocationID] [int] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ChampionshipID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblChampionships] ADD  DEFAULT ((0)) FOR [MultiLocatonFlg]
GO
ALTER TABLE [PTA].[tblChampionships] ADD  DEFAULT ((1)) FOR [ActiveFlg]
