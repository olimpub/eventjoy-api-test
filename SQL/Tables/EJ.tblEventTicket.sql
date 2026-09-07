SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventTicket](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[EventID] [bigint] NOT NULL,
	[Code] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[TicketName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Description] [nvarchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Price] [decimal](18, 2) NULL,
	[CurrencyCode] [char](3) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Capacity] [int] NULL,
	[RegistrationStart] [datetimeoffset](0) NOT NULL,
	[RegistrationEnd] [datetimeoffset](0) NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
	[TemplateID] [bigint] NULL
) ON [PRIMARY]

