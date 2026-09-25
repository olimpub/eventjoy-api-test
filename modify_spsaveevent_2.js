const fs = require('fs');
let code = fs.readFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', 'utf8');

// Replace the OP Settings Saving part with relational logic
const newLogic = `-- ==========================================
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
                    ShadowAwardFlg = @ShadowAwardFlg
                WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[EventSettings] (EventID, DeskCountHint, MaxTeamSize, PlannedDurationMin, ShadowAwardFlg)
                VALUES (@EventID, @DeskCountHint, @MaxTeamSize, @PlannedDurationMin, @ShadowAwardFlg);
            END

            -- Témakörök szinkronizációja
            DELETE FROM [OP].[EventSettingTopic] WHERE EventID = @EventID AND TopicID NOT IN (SELECT CAST(value AS INT) FROM OPENJSON(@TopicIdsJson));
            INSERT INTO [OP].[EventSettingTopic] (EventID, TopicID)
            SELECT @EventID, CAST(value AS INT) FROM OPENJSON(@TopicIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT TopicID FROM [OP].[EventSettingTopic] WHERE EventID = @EventID);

            -- Extra játékok szinkronizációja
            DELETE FROM [OP].[EventSettingExtraGame] WHERE EventID = @EventID AND ExtraGameId NOT IN (SELECT value FROM OPENJSON(@ExtraGameIdsJson));
            INSERT INTO [OP].[EventSettingExtraGame] (EventID, ExtraGameId)
            SELECT @EventID, value FROM OPENJSON(@ExtraGameIdsJson)
            WHERE value NOT IN (SELECT ExtraGameId FROM [OP].[EventSettingExtraGame] WHERE EventID = @EventID);

            -- Kabalák (EventSettingKabala) szinkronizációja
            DELETE FROM [OP].[EventSettingKabala] WHERE EventID = @EventID AND KabalaID NOT IN (SELECT CAST(value AS INT) FROM OPENJSON(@KabalaIdsJson));
            INSERT INTO [OP].[EventSettingKabala] (EventID, KabalaID)
            SELECT @EventID, CAST(value AS INT) FROM OPENJSON(@KabalaIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT KabalaID FROM [OP].[EventSettingKabala] WHERE EventID = @EventID);

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
        END`;

const regex = /-- ==========================================\r?\n\s*-- 7\.5 OP Beállítások \(Olimpub\)[\s\S]*?(?=-- ==========================================\r?\n\s*-- 8\. Szervező \(EventUser\) létrehozása)/;
code = code.replace(regex, newLogic + '\n\n        ');

fs.writeFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', code, 'utf8');
console.log('Saved corrected modifications to EJ.spSaveEvent.sql');
