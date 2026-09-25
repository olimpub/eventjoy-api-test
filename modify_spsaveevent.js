const fs = require('fs');
let code = fs.readFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', 'utf8');

// Strip BOM
code = code.replace(/\uFEFF/g, '');

// 1. Add @EventTypeID and @IsOP parsing
code = code.replace(
    /DECLARE @EventLocationID INT = JSON_VALUE\(@Json, '\$\.Event\.EventLocationID'\);/,
    `DECLARE @EventLocationID INT = JSON_VALUE(@Json, '$.Event.EventLocationID');
        DECLARE @EventTypeID INT = JSON_VALUE(@Json, '$.Event.EventTypeID');
        
        DECLARE @IsOP BIT = 0;
        IF @EventTypeID IS NOT NULL
        BEGIN
            SELECT @IsOP = ISNULL(OPFlg, 0) FROM [EJ].[tblEventType] WHERE id = @EventTypeID;
        END`
);

// 2. Modify #IncomingRoles extraction
code = code.replace(
    /SELECT \s*TempId,\s*TRY_CAST\(TempId AS INT\) AS RealEventRoleID,\s*RoleID,\s*ActiveFlg,\s*CAST\(NULL AS INT\) AS NewEventRoleID\s*INTO #IncomingRoles\s*FROM OPENJSON\(@Json, '\$\.Roles'\)\s*WITH \(TempId NVARCHAR\(100\), RoleID INT, ActiveFlg BIT\);/,
    `CREATE TABLE #IncomingRoles (
            TempId NVARCHAR(100),
            RealEventRoleID INT,
            RoleID INT,
            ActiveFlg BIT,
            NewEventRoleID INT
        );

        IF @IsOP = 1
        BEGIN
            -- Olimpub eseménynél fixen 3 role van, a frontend-ről jövőket felülírjuk
            INSERT INTO #IncomingRoles (TempId, RealEventRoleID, RoleID, ActiveFlg)
            SELECT 'auto_role_' + CAST(r.RoleID AS NVARCHAR(10)), er.id, r.RoleID, 1
            FROM (VALUES (1), (3), (7)) AS r(RoleID) -- 1: Szervező, 3: Játékos, 7: Játékmester
            LEFT JOIN [EJ].[tblEventRole] er ON er.EventID = @EventID AND er.RoleID = r.RoleID;
        END
        ELSE
        BEGIN
            INSERT INTO #IncomingRoles (TempId, RealEventRoleID, RoleID, ActiveFlg)
            SELECT 
                TempId,
                TRY_CAST(TempId AS INT) AS RealEventRoleID,
                RoleID,
                ActiveFlg
            FROM OPENJSON(@Json, '$.Roles')
            WITH (TempId NVARCHAR(100), RoleID INT, ActiveFlg BIT);
        END`
);

// 3. Modify #IncomingTickets extraction
code = code.replace(
    /SELECT \s*TempId,\s*TRY_CAST\(TempId AS INT\) AS RealEventTicketID,[\s\S]*?WITH \([\s\S]*?ActiveFlg BIT\s*\);/,
    `CREATE TABLE #IncomingTickets (
            TempId NVARCHAR(100), RealEventTicketID INT, Code NVARCHAR(100), TicketName NVARCHAR(200),
            Description NVARCHAR(MAX), Price DECIMAL(18,2), CurrencyCode NVARCHAR(3), Capacity INT,
            RegistrationStartAtUtc DATETIME2, RegistrationEndAtUtc DATETIME2, TemplateID INT, ActiveFlg BIT,
            NewEventTicketID INT
        );

        IF @IsOP = 1
        BEGIN
            -- Olimpub: Automatikus Játékos jegy
            INSERT INTO #IncomingTickets (
                TempId, RealEventTicketID, Code, TicketName, Description, Price, CurrencyCode, Capacity, ActiveFlg
            )
            SELECT 
                'auto_ticket_1', 
                (SELECT TOP 1 id FROM [EJ].[tblEventTicket] WHERE EventID = @EventID), 
                'KVZ_JATEKOS', N'Játékos Jegy', N'Automatikus jegy az Olimpub játékosoknak', 0, 'HUF', NULL, 1;
        END
        ELSE
        BEGIN
            INSERT INTO #IncomingTickets (
                TempId, RealEventTicketID, Code, TicketName, Description, Price, CurrencyCode, Capacity,
                RegistrationStartAtUtc, RegistrationEndAtUtc, TemplateID, ActiveFlg
            )
            SELECT 
                TempId, TRY_CAST(TempId AS INT), Code, TicketName, Description, Price, CurrencyCode, Capacity,
                CONVERT(DATETIME2, RegistrationStartAtUtc, 127), CONVERT(DATETIME2, RegistrationEndAtUtc, 127),
                TemplateID, ActiveFlg
            FROM OPENJSON(@Json, '$.Tickets')
            WITH (
                TempId NVARCHAR(100), Code NVARCHAR(100), TicketName NVARCHAR(200), Description NVARCHAR(MAX),
                Price DECIMAL(18,2), CurrencyCode NVARCHAR(3), Capacity INT, RegistrationStartAtUtc NVARCHAR(100),
                RegistrationEndAtUtc NVARCHAR(100), TemplateID INT, ActiveFlg BIT
            );
        END`
);

// 4. Modify ROLE TICKETS
code = code.replace(
    /INSERT INTO \[EJ\]\.\[tblEventRoleTicket\] \([\s\S]*?JOIN #IncomingTickets t ON t\.TempId = j\.TicketTempId;/,
    `IF @IsOP = 1
        BEGIN
            -- Olimpub: Csak a Játékos (RoleID = 3) kapja meg a jegyet
            INSERT INTO [EJ].[tblEventRoleTicket] (EventID, EventRoleID, EventTicketID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT 
                @EventID,
                r.NewEventRoleID,
                t.NewEventTicketID,
                1, @UserID, @Now, @Now
            FROM #IncomingRoles r
            CROSS JOIN #IncomingTickets t -- Mivel csak 1 jegyünk van (#IncomingTickets 1 sor)
            WHERE r.RoleID = 3;
        END
        ELSE
        BEGIN
            INSERT INTO [EJ].[tblEventRoleTicket] (EventID, EventRoleID, EventTicketID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT 
                @EventID,
                r.NewEventRoleID,
                t.NewEventTicketID,
                1, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.RoleTickets')
            WITH (RoleTempId NVARCHAR(100), TicketTempId NVARCHAR(100)) j
            JOIN #IncomingRoles r ON r.TempId = j.RoleTempId
            JOIN #IncomingTickets t ON t.TempId = j.TicketTempId;
        END`
);

// 5. Add OP Settings Saving
code = code.replace(
    /-- ==========================================\r?\n\s*-- 8\. Szervező \(EventUser\) létrehozása/,
    `-- ==========================================
        -- 7.5 OP Beállítások (Olimpub)
        -- ==========================================
        IF @IsOP = 1 AND JSON_QUERY(@Json, '$.OpSettings') IS NOT NULL
        BEGIN
            DECLARE @DeskCountHint INT = JSON_VALUE(@Json, '$.OpSettings.DeskCountHint');
            DECLARE @MaxTeamSize INT = ISNULL(JSON_VALUE(@Json, '$.OpSettings.MaxTeamSize'), 8);
            DECLARE @PlannedDurationMin INT = JSON_VALUE(@Json, '$.OpSettings.PlannedDurationMin');
            DECLARE @ShadowAwardFlg BIT = ISNULL(JSON_VALUE(@Json, '$.OpSettings.ShadowAwardFlg'), 1);
            DECLARE @TopicIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.TopicIds');
            DECLARE @ExtraGameIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.ExtraGameIds');
            DECLARE @KabalaIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.KabalaIds');

            IF EXISTS(SELECT 1 FROM [OP].[EventSettings] WHERE EventID = @EventID)
            BEGIN
                UPDATE [OP].[EventSettings]
                SET DeskCountHint = @DeskCountHint,
                    MaxTeamSize = @MaxTeamSize,
                    PlannedDurationMin = @PlannedDurationMin,
                    ShadowAwardFlg = @ShadowAwardFlg,
                    TopicIdsJson = @TopicIdsJson,
                    ExtraGameIdsJson = @ExtraGameIdsJson,
                    KabalaIdsJson = @KabalaIdsJson
                WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[EventSettings] (EventID, DeskCountHint, MaxTeamSize, PlannedDurationMin, ShadowAwardFlg, TopicIdsJson, ExtraGameIdsJson, KabalaIdsJson)
                VALUES (@EventID, @DeskCountHint, @MaxTeamSize, @PlannedDurationMin, @ShadowAwardFlg, @TopicIdsJson, @ExtraGameIdsJson, @KabalaIdsJson);
            END

            -- Csapatok szinkronizációja (Kabalák alapján)
            -- 1. Insert új csapatokat
            INSERT INTO [OP].[Team] (EventID, KabalaID, ActiveFlg)
            SELECT @EventID, CAST(value AS INT), 1
            FROM OPENJSON(@KabalaIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT KabalaID FROM [OP].[Team] WHERE EventID = @EventID);

            -- 2. Töröljük (inaktiváljuk) amiket kivettek, HA nincs TeamMember
            UPDATE t
            SET t.ActiveFlg = 0
            FROM [OP].[Team] t
            LEFT JOIN OPENJSON(@KabalaIdsJson) j ON t.KabalaID = CAST(j.value AS INT)
            WHERE t.EventID = @EventID AND j.value IS NULL
              AND NOT EXISTS (SELECT 1 FROM [OP].[TeamMember] tm WHERE tm.TeamID = t.id AND tm.ActiveFlg = 1);
              
            -- 3. Visszakapcsoljuk, ami eddig inaktív volt de visszajött
            UPDATE t
            SET t.ActiveFlg = 1
            FROM [OP].[Team] t
            JOIN OPENJSON(@KabalaIdsJson) j ON t.KabalaID = CAST(j.value AS INT)
            WHERE t.EventID = @EventID AND t.ActiveFlg = 0;
        END

        -- ==========================================
        -- 8. Szervező (EventUser) létrehozása`
);

// Restore standard sql start
code = 'SET QUOTED_IDENTIFIER ON;\nSET ANSI_NULLS ON;\nGO\n' + code;

fs.writeFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', code, 'utf8');
console.log('Saved modifications to EJ.spSaveEvent.sql');
