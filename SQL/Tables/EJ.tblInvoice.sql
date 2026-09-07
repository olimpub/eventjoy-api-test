SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblInvoice](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[SourceSystemId] [int] NOT NULL,
	[StatusId] [int] NOT NULL,
	[ExternalProviderId] [varchar](255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[InvoiceNumber] [varchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[FileUrl] [varchar](1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[TotalAmount] [decimal](18, 2) NULL,
	[Currency] [varchar](10) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[IssueDate] [date] NULL,
	[DueDate] [date] NULL,
	[CreatedAt] [datetime] NOT NULL,
	[UpdatedAt] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblInvoice] ADD  DEFAULT ('HUF') FOR [Currency]
GO
ALTER TABLE [EJ].[tblInvoice] ADD  DEFAULT (getutcdate()) FOR [CreatedAt]
