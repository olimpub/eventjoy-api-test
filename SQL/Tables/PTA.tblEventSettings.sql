SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventSettings](
	[EventID] [int] NOT NULL,
	[ChampinshipID] [int] NULL,
	[GameTypeID] [int] NOT NULL,
	[PairModeID] [int] NOT NULL,
	[Category] [tinyint] NOT NULL,
	[Point1] [smallint] NOT NULL,
	[Point2] [smallint] NOT NULL,
	[Point3] [smallint] NOT NULL,
	[Point4] [smallint] NOT NULL,
	[MaxParticipants] [smallint] NULL,
	[OrganizationGrpFlg] [bit] NOT NULL,
	[TeamGrpFlg] [bit] NOT NULL,
	[RegionGrpFlg] [bit] NOT NULL,
	[CompanyGrpFlg] [bit] NOT NULL,
	[PhotoUploadMadatoryFlg] [bit] NOT NULL,
	[ExtraPrizeFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[ShowUserPositionFlg] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[EventID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((1)) FOR [PairModeID]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((1)) FOR [Category]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((10)) FOR [Point1]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((7)) FOR [Point2]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((5)) FOR [Point3]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((3)) FOR [Point4]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [OrganizationGrpFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [TeamGrpFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [RegionGrpFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [CompanyGrpFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [PhotoUploadMadatoryFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((0)) FOR [ExtraPrizeFlg]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
GO
ALTER TABLE [PTA].[tblEventSettings] ADD  DEFAULT ((1)) FOR [ShowUserPositionFlg]
