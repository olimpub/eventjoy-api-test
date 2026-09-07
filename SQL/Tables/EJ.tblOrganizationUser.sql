SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblOrganizationUser](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[OrganizationID] [bigint] NOT NULL,
	[UserID] [bigint] NOT NULL,
	[OrganizationUserTypeID] [bigint] NOT NULL,
	[IsPrimary] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[PendingApprovalID] [bigint] NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblOrganizationUser] ADD  CONSTRAINT [DF_tblOrganizationUser_IsPrimary]  DEFAULT ((0)) FOR [IsPrimary]
GO
ALTER TABLE [EJ].[tblOrganizationUser] ADD  CONSTRAINT [DF_tblOrganizationUser_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUser] ADD  CONSTRAINT [DF_tblOrganizationUser_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblOrganizationUser] ADD  CONSTRAINT [DF_tblOrganizationUser_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
