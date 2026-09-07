SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spGetEventUserDataSheet]
    @EventUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnValue INT = 1;
    DECLARE @ReturnDescription NVARCHAR(MAX) = N'Success';

    BEGIN TRY
        DECLARE
            @EventID BIGINT,
            @RequesterRoleName NVARCHAR(200),
            @RequesterRoleCode NVARCHAR(100),
            @DataSheetType SMALLINT;

        DECLARE @Results TABLE
        (
            ResultNo SMALLINT,
            ResultName NVARCHAR(100)
        );

        -- context
        SELECT
            @EventID = EU.EventID,
            @RequesterRoleName = R.RoleName,
            @RequesterRoleCode = R.Code,
            @DataSheetType = RT.id
        FROM [EJ].[tblEventUser] EU
        LEFT JOIN [EJ].[tblEventRole] ER ON ER.ID = EU.EventRoleID
        LEFT JOIN [EJ].[tblRole] R ON R.ID = ER.RoleID
        LEFT JOIN [EJ].[tblRoleType] RT ON RT.ID = R.RoleTypeID
        WHERE EU.ID = @EventUserID;

        -- RS1: Return status
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- RS2: Result list  PTA pldny mindig kimegy (res, ha nem PTA / mg nincs adat)
        INSERT INTO @Results (ResultNo, ResultName)
        VALUES
            (1,  N'ReturnStatus'),
            (2,  N'ResultList'),
            (3,  N'ScreenContext'),
            (4,  N'Events'),
            (5,  N'EventSettings'),
            (6,  N'EventDesks'),
            (7,  N'EventRounds'),
            (8,  N'EventRoundDesks'),
            (9,  N'EventPlayers'),
            (10, N'GameSchedules'),
            (11, N'EventPrizes');

        IF (@DataSheetType = 1)
        BEGIN
            INSERT INTO @Results (ResultNo, ResultName)
            VALUES (12, N'EventParticpants'),
                   (13, N'EventPrograms');
        END
        ELSE
        BEGIN
            INSERT INTO @Results (ResultNo, ResultName)
            VALUES (12, N'EventPrograms');
        END


        SELECT * FROM @Results ORDER BY ResultNo;

        -- RS3: Screen context
        SELECT
            @EventUserID AS RequestEventUserID,
            @EventID AS EventID,
            @RequesterRoleCode AS RequesterRoleCode,
            @RequesterRoleName AS RequesterRoleName,
            @DataSheetType AS DataSheetType;

        -- RS4: Event Data
        SELECT *
        FROM [EJ].[tblEvent] ev
        WHERE ID = @EventID;

        -- RS5: PTA.tblEventSettings  0 vagy 1 sor
        SELECT *
        FROM [PTA].[tblEventSettings]
        WHERE EventID = @EventID;

        -- RS6: PTA.tblEventDesk
        SELECT *
        FROM [PTA].[tblEventDesk]
        WHERE EventID = @EventID
          AND ActiveFlg = 1;

        -- RS7: PTA.tblEventRound  EventID ktelez (esemny-pldny, nem a sablon)
        SELECT *
        FROM [PTA].[tblEventRound]
        WHERE EventID = @EventID;

        -- RS8: PTA.tblEventRoundDesk
        SELECT erd.*
        FROM [PTA].[tblEventRoundDesk] erd
        INNER JOIN [PTA].[tblEventRound] er ON er.EventRoundID = erd.EventRoundID
        WHERE er.EventID = @EventID
          AND erd.ActiveFlg = 1;

        -- RS9: PTA.tblEventPlayer
        SELECT *
        FROM [PTA].[tblEventPlayer]
        WHERE EventID = @EventID
          AND ActiveFlg = 1;

        -- RS10: PTA.tblGameSchedule
        SELECT gs.*
        FROM [PTA].[tblGameSchedule] gs
        INNER JOIN [PTA].[tblEventRoundDesk] erd ON erd.EventRoundDeskID = gs.EventRoundDeskID
        INNER JOIN [PTA].[tblEventRound] er ON er.EventRoundID = erd.EventRoundID
        WHERE er.EventID = @EventID
          AND gs.ActiveFlg = 1;

        -- RS11: PTA.tblEventPrize
        SELECT *
        FROM [PTA].[tblEventPrize]
        WHERE EventID = @EventID;

        -- RS12: Organizer datasheet (EJ rsztvevk)
        IF (@DataSheetType = 1)
        BEGIN
            SELECT eu.*, usr.FirstName, usr.LastName, usr.EmailAddress, usr.PhoneNumber
            FROM [EJ].[tblEventUser] eu
            INNER JOIN [EJ].[tblUser] usr ON usr.ID = eu.UserID
            Inner JOIN [EJ].[tblEventRole] er ON er.ID = eu.EventRoleID
            WHERE eu.EventID = @EventID
                --AND eu.ID <> @EventUserID
                AND eu.ActiveFlg = 1;
        END
    -- RS13: tblEventProgram
        SELECT ep.id, ep.EventID, ep.ProgramDateTime, ep.ProgramName, ep.ActiveFlg
        FROM [EJ].[tblEventProgram] ep
        WHERE ep.EventID = @EventID AND ep.ActiveFlg = 1
        ORDER BY ep.ProgramDateTime ASC;

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SET @ReturnDescription = ERROR_MESSAGE();

        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END

GO
