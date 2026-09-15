SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-------------------------------------------------------------------
-- 1. [PTA].[tblEventRoundStatusFlow] létrehozása
-------------------------------------------------------------------
CREATE TABLE [PTA].[tblEventRoundStatusFlow](
    [FlowID] [int] IDENTITY(1,1) NOT NULL,
    [FromStatusID] [int] NOT NULL,
    [ToStatusID] [int] NOT NULL,
    [CanUndoFlg] [bit] NOT NULL DEFAULT ((0)),
    [ActiveFlg] [bit] NOT NULL DEFAULT ((1)),
    [LastUpdatedUserID] [bigint] NULL,
    [createdAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset()),
    [updatedAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset()),
 PRIMARY KEY CLUSTERED 
(
    [FlowID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

-------------------------------------------------------------------
-- 2. Alapértelmezett Flow adatok (1-2, 2-3, 3-4, 3-5, 4-5) - Mind visszavonható
-------------------------------------------------------------------
INSERT INTO [PTA].[tblEventRoundStatusFlow] 
([FromStatusID], [ToStatusID], [CanUndoFlg], [ActiveFlg], [createdAt], [updatedAt])
VALUES 
(1, 2, 1, 1, sysdatetimeoffset(), sysdatetimeoffset()),
(2, 3, 1, 1, sysdatetimeoffset(), sysdatetimeoffset()),
(3, 4, 1, 1, sysdatetimeoffset(), sysdatetimeoffset()),
(3, 5, 1, 1, sysdatetimeoffset(), sysdatetimeoffset()),
(4, 5, 1, 1, sysdatetimeoffset(), sysdatetimeoffset())
GO

-------------------------------------------------------------------
-- 3. [PTA].[tblEventRoundStatusHistory] létrehozása
-------------------------------------------------------------------
CREATE TABLE [PTA].[tblEventRoundStatusHistory](
    [HistoryID] [bigint] IDENTITY(1,1) NOT NULL,
    [EventRoundID] [int] NOT NULL,
    [OldStatusID] [int] NULL,
    [NewStatusID] [int] NOT NULL,
    [ActiveFlg] [bit] NOT NULL DEFAULT ((1)),
    [UndoFlg] [bit] NOT NULL DEFAULT ((0)),
    [ChangedByUserID] [bigint] NOT NULL,
    [ChangeDate] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset()),
 PRIMARY KEY CLUSTERED 
(
    [HistoryID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
