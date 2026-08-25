DECLARE @FlowID BIGINT;

-- 1. Új Event Flow beszúrása
INSERT INTO [EJ].[tblEventFlow] ([Name], [ActiveFlg], [LastUpdatedUserID])
VALUES (N'Profitability flow', 1, 0);

-- Az imént beszúrt Flow ID-jának lekérése
SET @FlowID = SCOPE_IDENTITY();

-- 2. Státusz váltások (Lépések) beszúrása
-- A kérésnek megfelelően: CanUndoFlg = 1, CanCloseFlg = 0
INSERT INTO [EJ].[tblEventFlowStatus] 
    ([EventFlowID], [StepID], [FromStatusID], [ToStatusID], [CanUndoFlg], [CanCloseFlg], [ActiveFlg], [LastUpdatedUserID])
VALUES
    (@FlowID, 1,  NULL, 1,  1, 0, 1, 0), -- NULL -> Tervezés
    (@FlowID, 2,  1,    2,  1, 0, 1, 0), -- Tervezés -> Szervezés
    (@FlowID, 3,  2,    3,  1, 0, 1, 0), -- Szervezés -> Jelentkezés
    (@FlowID, 4,  3,    4,  1, 0, 1, 0), -- Jelentkezés -> Bejelentkezés
    (@FlowID, 5,  4,    9,  1, 0, 1, 0), -- Bejelentkezés -> Sorsolás
    (@FlowID, 6,  9,    10, 1, 0, 1, 0), -- Sorsolás -> Játék
    (@FlowID, 7,  10,   11, 1, 0, 1, 0), -- Játék -> Szünet
    (@FlowID, 8,  11,   5,  1, 0, 1, 0), -- Szünet -> Folyamatban
    (@FlowID, 9,  5,    6,  1, 0, 1, 0), -- Folyamatban -> Eredményhírdetés
    (@FlowID, 10, 6,    7,  1, 0, 1, 0), -- Eredményhírdetés -> Vége
    (@FlowID, 11, 1,    8,  1, 0, 1, 0); -- Tervezés -> Törölve (Példa a törlésre)

-- 3. Szerepkörök (Roles) hozzárendelése az összes új lépéshez
-- A korábbi flow alapján a RoleID-k: 1, 7, 10, 11
INSERT INTO [EJ].[tblEventFlowStatusRole] 
    ([EventFlowStatusID], [RoleID], [ActiveFlg], [LastUpdatedUserID])
SELECT 
    efs.ID, 
    roles.RoleID, 
    1, 
    0
FROM [EJ].[tblEventFlowStatus] efs
CROSS JOIN (
    SELECT 1 AS RoleID UNION ALL 
    SELECT 7 UNION ALL 
    SELECT 10 UNION ALL 
    SELECT 11
) roles
WHERE efs.EventFlowID = @FlowID;
GO
