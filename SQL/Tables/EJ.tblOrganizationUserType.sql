SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblOrganizationUserType](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Code] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Name] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[OwnerFlg] [bit] NOT NULL,
	[ManagerFlg] [bit] NOT NULL,
	[MemberFlg] [bit] NOT NULL,
	[NonMemberFlg] [bit] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblOrganizationUserType_Code] UNIQUE NONCLUSTERED 
(
	[Code] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblOrganizationUserType_Name] UNIQUE NONCLUSTERED 
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_OwnerFlg]  DEFAULT ((0)) FOR [OwnerFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_ManagerFlg]  DEFAULT ((0)) FOR [ManagerFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_MemberFlg]  DEFAULT ((0)) FOR [MemberFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_NonMemberFlg]  DEFAULT ((0)) FOR [NonMemberFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblOrganizationUserType] ADD  CONSTRAINT [DF_tblOrganizationUserType_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
