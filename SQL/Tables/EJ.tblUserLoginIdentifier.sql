SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUserLoginIdentifier](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[IdentifierTypeID] [int] NOT NULL,
	[IdentifierValueRaw] [nvarchar](320) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IdentifierValueNormalized] [nvarchar](320) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IsPrimary] [bit] NOT NULL,
	[IsVerified] [bit] NOT NULL,
	[VerifiedAtUtc] [datetimeoffset](0) NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblUserLoginIdentifier] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO
CREATE NONCLUSTERED INDEX [IX_tblUserLoginIdentifier_LoginLookup] ON [EJ].[tblUserLoginIdentifier]
(
	[IdentifierValueNormalized] ASC,
	[IdentifierTypeID] ASC,
	[IsVerified] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblUserLoginIdentifier_Type_Normalized_Active] ON [EJ].[tblUserLoginIdentifier]
(
	[IdentifierTypeID] ASC,
	[IdentifierValueNormalized] ASC
)
WHERE ([ActiveFlg]=(1))
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblUserLoginIdentifier_User_Type_Primary] ON [EJ].[tblUserLoginIdentifier]
(
	[UserID] ASC,
	[IdentifierTypeID] ASC
)
WHERE ([IsPrimary]=(1) AND [ActiveFlg]=(1))
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD  CONSTRAINT [DF_tblUserLoginIdentifier_IsPrimary]  DEFAULT ((0)) FOR [IsPrimary]
GO
ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD  CONSTRAINT [DF_tblUserLoginIdentifier_IsVerified]  DEFAULT ((0)) FOR [IsVerified]
GO
ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD  CONSTRAINT [DF_tblUserLoginIdentifier_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD  CONSTRAINT [DF_tblUserLoginIdentifier_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD  CONSTRAINT [DF_tblUserLoginIdentifier_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
