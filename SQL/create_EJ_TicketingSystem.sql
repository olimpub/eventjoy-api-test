SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-------------------------------------------------------------------
-- 1. [EJ].[tblTicketType] (Típusok)
-------------------------------------------------------------------
CREATE TABLE [EJ].[tblTicketType](
    [TicketTypeID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [TypeName] [nvarchar](100) NOT NULL,
    [ActiveFlg] [bit] NOT NULL DEFAULT ((1))
) ON [PRIMARY]
GO

INSERT INTO [EJ].[tblTicketType] (TypeName) VALUES 
(N'Hiba'), 
(N'Fejlesztési igény'), 
(N'Kérdés')
GO

-------------------------------------------------------------------
-- 2. [EJ].[tblTicketStatus] (Státuszok)
-------------------------------------------------------------------
CREATE TABLE [EJ].[tblTicketStatus](
    [TicketStatusID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [StatusName] [nvarchar](100) NOT NULL,
    [IsClosedState] [bit] NOT NULL DEFAULT ((0)),
    [ActiveFlg] [bit] NOT NULL DEFAULT ((1))
) ON [PRIMARY]
GO

INSERT INTO [EJ].[tblTicketStatus] (StatusName, IsClosedState) VALUES 
(N'Függőben', 0),    -- 1
(N'Folyamatban', 0), -- 2
(N'Ütemezve', 0),    -- 3
(N'Kiadva', 1),      -- 4
(N'Elutasítva', 1),  -- 5
(N'Visszavont', 1)   -- 6
GO

-------------------------------------------------------------------
-- 3. [EJ].[tblTicketStatusFlow] (Átmenetek gráfja)
-------------------------------------------------------------------
CREATE TABLE [EJ].[tblTicketStatusFlow](
    [FlowID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [FromStatusID] [int] NOT NULL,
    [ToStatusID] [int] NOT NULL,
    [ActiveFlg] [bit] NOT NULL DEFAULT ((1))
) ON [PRIMARY]
GO

-- Alapértelmezett flow felöltése
INSERT INTO [EJ].[tblTicketStatusFlow] (FromStatusID, ToStatusID) VALUES 
-- Függőből mehet:
(1, 2), (1, 3), (1, 5), (1, 6),
-- Folyamatban lévőből mehet:
(2, 3), (2, 4), (2, 6),
-- Ütemezettből mehet:
(3, 2), (3, 4), (3, 6)
GO

-------------------------------------------------------------------
-- 4. [EJ].[tblTicket] (Maguk a hibajegyek)
-------------------------------------------------------------------
CREATE TABLE [EJ].[tblTicket](
    [TicketID] [bigint] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [ReporterUserID] [bigint] NOT NULL,
    [Title] [nvarchar](255) NOT NULL,
    [Description] [nvarchar](max) NOT NULL,
    [TicketTypeID] [int] NOT NULL,
    [StatusID] [int] NOT NULL,
    [TargetVersion] [nvarchar](50) NULL,
    [AIAnalysisLog] [nvarchar](max) NULL,
    [createdAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset()),
    [updatedAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset())
) ON [PRIMARY]
GO

-------------------------------------------------------------------
-- 5. [EJ].[tblTicketComment] (Jegyzetek / AI / Admin válaszok)
-------------------------------------------------------------------
CREATE TABLE [EJ].[tblTicketComment](
    [CommentID] [bigint] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [TicketID] [bigint] NOT NULL,
    [UserID] [bigint] NULL, -- NULL, ha rendszer/AI írta
    [CommentText] [nvarchar](max) NOT NULL,
    [IsSystemMessage] [bit] NOT NULL DEFAULT ((0)),
    [createdAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset())
) ON [PRIMARY]
GO
