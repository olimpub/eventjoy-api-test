SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblApprovalPermission](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[ApprovalID] [bigint] NOT NULL,
	[RoleID] [bigint] NULL,
	[OrganizationUserTypeID] [bigint] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblApprovalPermission_Approval_OrgType] ON [EJ].[tblApprovalPermission]
(
	[ApprovalID] ASC,
	[OrganizationUserTypeID] ASC
)
WHERE ([OrganizationUserTypeID] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblApprovalPermission_Approval_Role] ON [EJ].[tblApprovalPermission]
(
	[ApprovalID] ASC,
	[RoleID] ASC
)
WHERE ([RoleID] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblApprovalPermission] ADD  CONSTRAINT [DF_tblApprovalPermission_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblApprovalPermission] ADD  CONSTRAINT [DF_tblApprovalPermission_createdAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblApprovalPermission] ADD  CONSTRAINT [DF_tblApprovalPermission_updatedAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [updatedAt]
