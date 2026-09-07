SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventTypeOwner](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventTypeID] [bigint] NOT NULL,
	[UserID] [bigint] NOT NULL,
	[CanAddOwnerFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL
) ON [PRIMARY]

