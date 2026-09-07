SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventRound](
	[EventRoundID] [int] IDENTITY(1,1) NOT NULL,
	[RoundID] [int] NOT NULL,
	[EventRoundStatusID] [int] NOT NULL,
	[NoOfDesks] [int] NOT NULL,
	[EventID] [int] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[EventRoundID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventRound] ADD  DEFAULT ((0)) FOR [NoOfDesks]
GO
ALTER TABLE [PTA].[tblEventRound] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventRound] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
