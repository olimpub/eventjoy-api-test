SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUser](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[FirstName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[LastName] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Password] [nvarchar](512) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[EmailAddress] [nvarchar](300) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[StatusID] [int] NOT NULL,
	[UnsuccessfulAttempts] [smallint] NULL,
	[LastUpdatedUserID] [int] NULL,
	[createdAt] [datetimeoffset](7) NOT NULL,
	[updatedAt] [datetimeoffset](7) NOT NULL,
	[PasswordUID] [uniqueidentifier] NULL,
	[PasswordUIDValid] [datetimeoffset](7) NULL,
	[GoogleId] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[FacebookId] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[AppleId] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[PhoneNumber] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ValidationCode] [varchar](10) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ValidationCodeExpiry] [datetimeoffset](7) NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UQ_tblUser_AppleId] ON [EJ].[tblUser]
(
	[AppleId] ASC
)
WHERE ([AppleId] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UQ_tblUser_FacebookId] ON [EJ].[tblUser]
(
	[FacebookId] ASC
)
WHERE ([FacebookId] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [UQ_tblUser_GoogleId] ON [EJ].[tblUser]
(
	[GoogleId] ASC
)
WHERE ([GoogleId] IS NOT NULL)
WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblUser] ADD  DEFAULT ((1)) FOR [StatusID]
GO
ALTER TABLE [EJ].[tblUser] ADD  DEFAULT ((0)) FOR [UnsuccessfulAttempts]
GO
ALTER TABLE [EJ].[tblUser] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblUser] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
