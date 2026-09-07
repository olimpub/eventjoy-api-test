SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventUser](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NOT NULL,
	[UserID] [bigint] NOT NULL,
	[EventRoleID] [bigint] NOT NULL,
	[EventUserStatusID] [bigint] NULL,
	[EventTicketID] [bigint] NULL,
	[InvitationID] [bigint] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[InvoiceId] [int] NULL,
	[EventUserUID] [uniqueidentifier] NULL,
	[PrevEventUserStatusID] [int] NULL,
	[Rating] [tinyint] NULL,
	[RatingComment] [nvarchar](2000) NULL,
	CONSTRAINT [CK_tblEventUser_Rating] CHECK ([Rating] IS NULL OR ([Rating] BETWEEN 1 AND 5))
) ON [PRIMARY]
