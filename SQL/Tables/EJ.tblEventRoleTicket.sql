SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventRoleTicket](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NOT NULL,
	[EventRoleID] [bigint] NOT NULL,
	[EventTicketID] [bigint] NOT NULL,
	[Capacity] [int] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL
) ON [PRIMARY]

