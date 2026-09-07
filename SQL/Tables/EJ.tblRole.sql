SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblRole](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Code] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[RoleName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Description] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[RoleTypeID] [bigint] NULL,
	[SystemFlg] [bit] NOT NULL,
	[OwnerFlg] [bit] NOT NULL
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblRole] ADD  DEFAULT ((0)) FOR [SystemFlg]
GO
ALTER TABLE [EJ].[tblRole] ADD  DEFAULT ((0)) FOR [OwnerFlg]
