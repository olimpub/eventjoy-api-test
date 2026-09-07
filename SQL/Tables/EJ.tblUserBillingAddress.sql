SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUserBillingAddress](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[IsDefault] [bit] NOT NULL,
	[BillingName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[IsCompany] [bit] NOT NULL,
	[CompanyName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CompanyTaxNumber] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CompanyVatNumber] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[CountryCode] [nvarchar](2) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[PostalCode] [nvarchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[City] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AddressLine1] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AddressLine2] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StateOrRegion] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[BillingEmail] [nvarchar](320) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[BillingPhone] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblUserBillingAddress] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblUserBillingAddress] ADD  CONSTRAINT [DF_tblUserBillingAddress_IsDefault]  DEFAULT ((0)) FOR [IsDefault]
GO
ALTER TABLE [EJ].[tblUserBillingAddress] ADD  CONSTRAINT [DF_tblUserBillingAddress_IsCompany]  DEFAULT ((0)) FOR [IsCompany]
GO
ALTER TABLE [EJ].[tblUserBillingAddress] ADD  CONSTRAINT [DF_tblUserBillingAddress_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblUserBillingAddress] ADD  CONSTRAINT [DF_tblUserBillingAddress_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblUserBillingAddress] ADD  CONSTRAINT [DF_tblUserBillingAddress_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
