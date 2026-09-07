CREATE TABLE [EJ].[tblSystemParam](
    [id] [int] IDENTITY(1,1) NOT NULL,
    [ParamName] [nvarchar](100) NOT NULL,
    [ParamValue] [nvarchar](MAX) NOT NULL,
    [Description] [nvarchar](500) NULL,
    [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblSystemParam_ActiveFlg] DEFAULT ((1)),
    [LastUpdatedUserID] [int] NULL,
    [createdAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblSystemParam_createdAt] DEFAULT (sysdatetimeoffset()),
    [updatedAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblSystemParam_updatedAt] DEFAULT (sysdatetimeoffset()),
 CONSTRAINT [PK_tblSystemParam] PRIMARY KEY CLUSTERED 
(
    [id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE UNIQUE NONCLUSTERED INDEX [UIX_tblSystemParam_ParamName] ON [EJ].[tblSystemParam]
(
    [ParamName] ASC
) WHERE ([ActiveFlg]=(1))
GO

-- Alapértelmezett értékek
INSERT INTO [EJ].[tblSystemParam] (ParamName, ParamValue, Description)
VALUES 
    ('RunningMode', 'Test', 'Aktuális futási környezet: Local, Test vagy Live'),
    ('FrontendBaseUrl_Local', 'http://localhost:9000', 'Frontend elérhetősége lokális fejlesztéshez'),
    ('FrontendBaseUrl_Test', 'https://testapp.eventjoy.hu', 'Frontend elérhetősége teszt/staging környezethez'),
    ('FrontendBaseUrl_Live', 'https://app.eventjoy.hu', 'Frontend elérhetősége éles környezethez');
GO
