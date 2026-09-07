SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventRoundStatus](
	[EventRoundStatusID] [int] IDENTITY(1,1) NOT NULL,
	[SName] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[EventRoundStatusID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_PTA_tblEventRoundStatus_SName] UNIQUE NONCLUSTERED 
(
	[SName] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventRoundStatus] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [PTA].[tblEventRoundStatus] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventRoundStatus] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
