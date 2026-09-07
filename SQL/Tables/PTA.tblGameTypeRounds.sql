SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblGameTypeRounds](
	[RoundID] [int] IDENTITY(1,1) NOT NULL,
	[GameTypeID] [int] NULL,
	[OrderIndex] [int] NOT NULL,
	[RName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[QualifyToNextRound] [smallint] NULL,
	[ResultsVisibleFlg] [bit] NOT NULL,
	[FinalRoundFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[RoundID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblGameTypeRounds] ADD  DEFAULT ((1)) FOR [ResultsVisibleFlg]
GO
ALTER TABLE [PTA].[tblGameTypeRounds] ADD  DEFAULT ((0)) FOR [FinalRoundFlg]
GO
ALTER TABLE [PTA].[tblGameTypeRounds] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblGameTypeRounds] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblGameTypeRounds] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
