SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblGameSchedule](
	[GameScheduleID] [int] IDENTITY(1,1) NOT NULL,
	[EventRoundDeskID] [int] NOT NULL,
	[PlayerID] [int] NOT NULL,
	[PlayColorHex] [varchar](7) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Amount] [int] NULL,
	[OnTrack] [int] NULL,
	[Position] [int] NULL,
	[ResultPoint] [int] NULL,
	[FinalPoint] [decimal](18, 2) NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[GameScheduleID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblGameSchedule] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblGameSchedule] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblGameSchedule] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
