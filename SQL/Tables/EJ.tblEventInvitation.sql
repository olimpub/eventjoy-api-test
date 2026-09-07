SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventInvitation](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NOT NULL,
	[EmailAddress] [nvarchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[FirstName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[LastName] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[PhoneNumber] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[EventRoleID] [bigint] NOT NULL,
	[UserID] [bigint] NULL,
	[InvitationCode] [nvarchar](6) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[InvitationUID] [uniqueidentifier] NOT NULL,
	[AssignedFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblEventInvitation] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT (CONVERT([nvarchar](6),abs(checksum(newid()))%(900000)+(100000))) FOR [InvitationCode]
GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT (newid()) FOR [InvitationUID]
GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT ((0)) FOR [AssignedFlg]
GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventInvitation] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
