IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblEventActionRule]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblEventActionRule] (
        ID INT IDENTITY(1,1) PRIMARY KEY,
        [Action] NVARCHAR(64) NOT NULL,
        ToValue INT NULL,
        
        -- Jogosultságok (Ki hívhatja meg?)
        OrganizerExecuteFlg BIT NOT NULL DEFAULT 1,
        ContributorExecuteFlg BIT NOT NULL DEFAULT 0,
        ParticipantExecuteFlg BIT NOT NULL DEFAULT 0,
        
        -- Értesítések (SignalR)
        OrganizerNotifyFlg BIT NOT NULL DEFAULT 0,
        ContributorNotifyFlg BIT NOT NULL DEFAULT 0,
        ParticipantNotifyFlg BIT NOT NULL DEFAULT 0,
        UserNotifyFlg BIT NOT NULL DEFAULT 0,
        GroupNotifyFlg BIT NOT NULL DEFAULT 0,
        
        ActiveFlg BIT NOT NULL DEFAULT 1,
        LastUpdatedUserID INT NOT NULL DEFAULT 1,
        createdAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        updatedAt DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );
END
GO

-- Tábla ürítése a tiszta betöltéshez
TRUNCATE TABLE [EJ].[tblEventActionRule];
GO

-- SZABÁLYOK FELTÖLTÉSE A KÉRT MÁTRIX ALAPJÁN
INSERT INTO [EJ].[tblEventActionRule] 
    ([Action], OrganizerNotifyFlg, ContributorNotifyFlg, ParticipantNotifyFlg, UserNotifyFlg, GroupNotifyFlg, OrganizerExecuteFlg, ContributorExecuteFlg, ParticipantExecuteFlg)
VALUES
-- 1. EventUser.SetStatus: Szervezők és érintett User
('EventUser.SetStatus', 1, 0, 0, 1, 0, 1, 0, 0),

-- 2. Event.SetStatus: Mindenki
('Event.SetStatus', 1, 1, 1, 0, 0, 1, 0, 0),

-- 3. EventUser.Apply: Szervezők és érintett User
('EventUser.Apply', 1, 0, 0, 1, 0, 1, 0, 1),

-- 4. EventUser.Remove: Szervezők és érintett User
('EventUser.Remove', 1, 0, 0, 1, 0, 1, 0, 0),

-- 5. Pta.ReplaceDraw: Mindenki
('Pta.ReplaceDraw', 1, 1, 1, 0, 0, 1, 0, 0),

-- 6. Pta.SetRoundStatus: Mindenki
('Pta.SetRoundStatus', 1, 1, 1, 0, 0, 1, 1, 0),

-- 7. Pta.SetDeskResults: Szervezők, Közreműködők, érintett Group
('Pta.SetDeskResults', 1, 1, 0, 0, 1, 1, 1, 0),

-- 8. Pta.ClaimDesk: Szervezők, Közreműködők, érintett Group
('Pta.ClaimDesk', 1, 1, 0, 0, 1, 1, 1, 0),

-- 9. Pta.PatchDesk: Szervezők, Közreműködők
('Pta.PatchDesk', 1, 1, 0, 0, 0, 1, 1, 0),

-- 10. Pta.Reset: Mindenki
('Pta.Reset', 1, 1, 1, 0, 0, 1, 0, 0);
GO
