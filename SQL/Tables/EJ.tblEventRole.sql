SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventRole](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NOT NULL,
	[RoleID] [bigint] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL
) ON [PRIMARY]

