SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblOrganization](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ShortName] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Email] [nvarchar](320) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Phone] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TaxId] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CountryCode] [nvarchar](2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PostalCode] [nvarchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[City] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[AddressLine1] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[AddressLine2] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[OrganizationTypeID] [bigint] NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblOrganization_Name] ON [EJ].[tblOrganization]
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblOrganization_ShortName] ON [EJ].[tblOrganization]
(
	[ShortName] ASC
)
WHERE ([ShortName] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblOrganization] ADD  CONSTRAINT [DF_tblOrganization_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblOrganization] ADD  CONSTRAINT [DF_tblOrganization_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblOrganization] ADD  CONSTRAINT [DF_tblOrganization_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
