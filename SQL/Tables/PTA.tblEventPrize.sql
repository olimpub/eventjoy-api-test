SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventPrize](
	[EventID] [int] NOT NULL,
	[PrizeID] [int] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL
) ON [PRIMARY]

GO
ALTER TABLE [PTA].[tblEventPrize] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [PTA].[tblEventPrize] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
