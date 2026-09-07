CREATE OR ALTER PROCEDURE [EJ].[spChangeEvent]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @Action NVARCHAR(64) = JSON_VALUE(@Json, '$.Action');
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'EventID is required', 1;
        END

        IF @Action = N'Event.SetStatus'
        BEGIN
            DECLARE @EventToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            DECLARE @EventPrevStatusID INT = JSON_VALUE(@Json, '$.Payload.PrevStatusID');
            
            UPDATE [EJ].[tblEvent]
            SET EventStatusID = @EventToStatusID,
                PrevEventStatusID = @EventPrevStatusID,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id = @EventID;
        END
        ELSE IF @Action = N'EventUser.SetStatus'
        BEGIN
            DECLARE @EuToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            DECLARE @EuPrevStatusID INT = JSON_VALUE(@Json, '$.Payload.PrevStatusID');
            
            DECLARE @TargetEventUserIDs TABLE (ID INT);

            -- 1. Batch ID-k
            IF JSON_QUERY(@Json, '$.Payload.EventUserIDs') IS NOT NULL
            BEGIN
                INSERT INTO @TargetEventUserIDs (ID)
                SELECT CAST(value AS INT)
                FROM OPENJSON(@Json, '$.Payload.EventUserIDs');
            END
            -- 2. Single ID
            ELSE IF JSON_VALUE(@Json, '$.Payload.EventUserID') IS NOT NULL
            BEGIN
                INSERT INTO @TargetEventUserIDs (ID)
                VALUES (JSON_VALUE(@Json, '$.Payload.EventUserID'));
            END
            -- 3. UID
            ELSE IF JSON_VALUE(@Json, '$.Payload.EventUserUID') IS NOT NULL
            BEGIN
                DECLARE @EuUID UNIQUEIDENTIFIER = CAST(JSON_VALUE(@Json, '$.Payload.EventUserUID') AS UNIQUEIDENTIFIER);
                INSERT INTO @TargetEventUserIDs (ID)
                SELECT id FROM [EJ].[tblEventUser] WHERE EventUserUID = @EuUID AND EventID = @EventID;
            END

            -- Update EventUsers
            UPDATE [EJ].[tblEventUser]
            SET EventUserStatusID = @EuToStatusID,
                PrevEventUserStatusID = CASE WHEN @EuPrevStatusID IS NULL THEN PrevEventUserStatusID ELSE @EuPrevStatusID END,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id IN (SELECT ID FROM @TargetEventUserIDs)
              AND EventID = @EventID;
        END
        ELSE IF @Action = N'EventUser.Apply'
        BEGIN
            DECLARE @ApplyTicketID INT = JSON_VALUE(@Json, '$.Payload.EventTicketID');
            -- Kikeressük az adott jegyhez tartozó RoleID-t
            DECLARE @ApplyRoleID INT = (SELECT TOP 1 EventRoleID FROM [EJ].[tblEventRoleTicket] WHERE EventTicketID = @ApplyTicketID);
            
            INSERT INTO [EJ].[tblEventUser] (EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, @UserID, @ApplyRoleID, @ApplyTicketID, 1, 1, @UserID, @Now, @Now);
        END
        ELSE IF @Action = N'EventUser.Remove'
        BEGIN
            DECLARE @RemoveEventUserID INT = JSON_VALUE(@Json, '$.Payload.EventUserID');
            UPDATE [EJ].[tblEventUser] 
            SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now 
            WHERE id = @RemoveEventUserID AND EventID = @EventID;
        END
        ELSE IF @Action = N'Pta.ReplaceDraw'
        BEGIN
            -- Delete existing draws (Set ActiveFlg = 0 for tables that have it)
            UPDATE [PTA].[tblEventDesk] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            
            UPDATE [PTA].[tblEventRound] SET LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            
            UPDATE [PTA].[tblEventRoundDesk] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventRoundID IN (SELECT EventRoundID FROM [PTA].[tblEventRound] WHERE EventID = @EventID);
            UPDATE [PTA].[tblEventPlayer] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            UPDATE [PTA].[tblGameSchedule] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE PlayerID IN (SELECT EventPlayerID FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID);

            -- INSERT Desks
            DECLARE @NewDesks TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventDesk] AS target
            USING (
                SELECT TempId, DeskNo, ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.Desks')
                WITH (TempId NVARCHAR(64), DeskNo INT, ActiveFlg BIT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, DeskNumber, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.DeskNo, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventDeskID, source.TempId INTO @NewDesks;

            -- INSERT Rounds
            DECLARE @NewRounds TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventRound] AS target
            USING (
                SELECT TempId, RoundID, EventRoundStatusID, NoOfDesks
                FROM OPENJSON(@Json, '$.Payload.Rounds')
                WITH (TempId NVARCHAR(64), RoundID INT, EventRoundStatusID INT, NoOfDesks INT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, RoundID, EventRoundStatusID, NoOfDesks, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.RoundID, source.EventRoundStatusID, source.NoOfDesks, @UserID, @Now, @Now)
            OUTPUT inserted.EventRoundID, source.TempId INTO @NewRounds;

            -- INSERT RoundDesks
            DECLARE @NewRoundDesks TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventRoundDesk] AS target
            USING (
                SELECT j.TempId, d.InsertedID AS DeskID, r.InsertedID AS RoundID, j.GameMasterUserID, j.ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.RoundDesks')
                WITH (TempId NVARCHAR(64), DeskTempId NVARCHAR(64), RoundTempId NVARCHAR(64), GameMasterUserID INT, ActiveFlg BIT) j
                JOIN @NewDesks d ON j.DeskTempId = d.TempId
                JOIN @NewRounds r ON j.RoundTempId = r.TempId
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventRoundID, EventDeskID, GameMasterUserID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (source.RoundID, source.DeskID, source.GameMasterUserID, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventRoundDeskID, source.TempId INTO @NewRoundDesks;

            -- INSERT Players
            DECLARE @NewPlayers TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventPlayer] AS target
            USING (
                SELECT TempId, EventUserID, Name, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.Players')
                WITH (TempId NVARCHAR(64), EventUserID INT, Name NVARCHAR(200), TeamName NVARCHAR(200), CompanyName NVARCHAR(200), OrganizationName NVARCHAR(200), RegionName NVARCHAR(200), ActiveFlg BIT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, EventUserID, NickName, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.EventUserID, source.Name, source.TeamName, source.CompanyName, source.OrganizationName, source.RegionName, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventPlayerID, source.TempId INTO @NewPlayers;

            -- INSERT Schedules
            INSERT INTO [PTA].[tblGameSchedule] (EventRoundDeskID, PlayerID, PlayColorHex, Amount, OnTrack, Position, ResultPoint, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT rd.InsertedID, p.InsertedID, j.ColorHex, j.Amount, j.OnTrack, j.Position, j.ResultPoint, j.ActiveFlg, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.Payload.Schedules')
            WITH (RoundDeskTempId NVARCHAR(64), PlayerTempId NVARCHAR(64), ColorHex NVARCHAR(10), Amount INT, OnTrack INT, Position INT, ResultPoint INT, ActiveFlg BIT) j
            JOIN @NewRoundDesks rd ON j.RoundDeskTempId = rd.TempId
            JOIN @NewPlayers p ON j.PlayerTempId = p.TempId;

        END
        ELSE IF @Action = N'Pta.SetRoundStatus'
        BEGIN
            DECLARE @RoundID INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @RoundStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            
            -- 1. Forduló státusz frissítése
            UPDATE [PTA].[tblEventRound] 
            SET EventRoundStatusID = @RoundStatusID, 
                LastUpdatedUserID = @UserID, 
                updatedAt = @Now 
            WHERE EventRoundID = @RoundID AND EventID = @EventID;

            -- Opcionálisan ide kerülhet egy IF ág is (pl: IF @RoundStatusID = 3), ha  
            -- csak bizonyos státuszra (lezártra) akarod újraszámolni a pontokat.
            -- 2. Aggregáció (Eredmények összesítése EventPlayer szinten)
            ;WITH AggregatedScores AS (
                SELECT 
                    s.PlayerID, 
                    SUM(ISNULL(CAST(s.ResultPoint AS DECIMAL(18,2)), 0)) AS TotalResultPoint,
                    SUM(ISNULL(CAST(s.Amount AS DECIMAL(18,2)), 0)) AS TotalAmount
                FROM [PTA].[tblGameSchedule] s
                INNER JOIN [PTA].[tblEventRoundDesk] rd ON s.EventRoundDeskID = rd.EventRoundDeskID
                INNER JOIN [PTA].[tblEventRound] r ON rd.EventRoundID = r.EventRoundID
                WHERE r.EventID = @EventID 
                  AND s.ActiveFlg = 1
                GROUP BY s.PlayerID
            )
            UPDATE p
            SET 
                p.FinalPoint = a.TotalResultPoint,
                p.FinalTruckPoint = a.TotalAmount,
                p.LastUpdatedUserID = @UserID,
                p.updatedAt = @Now
            FROM [PTA].[tblEventPlayer] p
            INNER JOIN AggregatedScores a ON p.EventPlayerID = a.PlayerID
            WHERE p.EventID = @EventID;
        END
        ELSE IF @Action = N'Pta.SetDeskResults'
        BEGIN
            DECLARE @RoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');

            UPDATE s
            SET Amount = j.Amount,
                OnTrack = j.OnTrack,
                Position = j.Position,
                ResultPoint = j.ResultPoint,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            FROM [PTA].[tblGameSchedule] s
            JOIN OPENJSON(@Json, '$.Payload.Seats')
            WITH (PlayerID INT, Amount DECIMAL(18,2), OnTrack INT, Position INT, ResultPoint INT) j
            ON s.PlayerID = j.PlayerID
            WHERE s.EventRoundDeskID = @RoundDeskID;
        END
        ELSE IF @Action = N'Pta.ClaimDesk'
        BEGIN
            DECLARE @ClaimRoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');
            DECLARE @GameMasterUserID INT = JSON_VALUE(@Json, '$.Payload.GameMasterUserID');

            IF @ClaimRoundDeskID IS NOT NULL
            BEGIN
                UPDATE [PTA].[tblEventRoundDesk] 
                SET GameMasterUserID = @GameMasterUserID, LastUpdatedUserID = @UserID, updatedAt = @Now 
                WHERE EventRoundDeskID = @ClaimRoundDeskID;
            END
        END
        ELSE IF @Action = N'Pta.PatchDesk'
        BEGIN
            DECLARE @PatchRoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');
            DECLARE @PatchPhotoUrl NVARCHAR(500) = JSON_VALUE(@Json, '$.Payload.PhotoUrl');
            
            UPDATE [PTA].[tblEventRoundDesk]
            SET AzurePhotoUrl = COALESCE(@PatchPhotoUrl, AzurePhotoUrl),
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventRoundDeskID = @PatchRoundDeskID;
        END
        ELSE IF @Action = N'Pta.Reset'
        BEGIN
            DECLARE @ResetToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            
            UPDATE [PTA].[tblEventDesk] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            UPDATE [PTA].[tblEventRound] SET LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            UPDATE [PTA].[tblEventRoundDesk] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventRoundID IN (SELECT EventRoundID FROM [PTA].[tblEventRound] WHERE EventID = @EventID);
            UPDATE [PTA].[tblEventPlayer] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventID = @EventID;
            UPDATE [PTA].[tblGameSchedule] SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE PlayerID IN (SELECT EventPlayerID FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID);

            UPDATE [EJ].[tblEvent]
            SET EventStatusID = @ResetToStatusID,
                PrevEventStatusID = NULL,
                PendingApprovalID = NULL,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id = @EventID;
        END
        ELSE
        BEGIN
            THROW 50002, N'Ismeretlen Action', 1;
        END

        COMMIT TRANSACTION;
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID, @Action AS Action;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS Action;
    END CATCH
END
GO
