SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ==============================================================================================
-- [EJ].[spGetEventData]
-- FelelĹ‘ssĂ©g: Az esemĂ©nyek Ă©s a hozzĂˇjuk kapcsolĂłdĂł Ă¶sszes rĂ©szletes adat lekĂ©rĂ©se (Discovery + My Events).
-- ==============================================================================================

CREATE OR ALTER PROCEDURE [EJ].[spGetEventData]
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX)

    BEGIN TRY
        SET @ReturnValue = 1
        SET @ReturnDescription = 'Success'

        -- RS 1: VisszatĂ©rĂ©si Ăˇllapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription

        -- SegĂ©dtĂˇbla a kigyĹ±jtĂ¶tt relevĂˇns EventID-knek, hogy ne kelljen tĂ¶bbszĂ¶r futtatni a bonyolult feltĂ©telt
        DECLARE @RelevantEvents TABLE (EventID BIGINT PRIMARY KEY, LocationID BIGINT);
         
        DECLARE  @Results TABLE(
                ResultNo SMALLINT,
                ResultName NVARCHAR(100)
                )

         INSERT INTO @Results (ResultNo, ResultName)
                VALUES
                (1, 'ReturnStatus'),
                (2, 'ResultList'),
                (3, 'Events'),
                (4, 'Invitations'),
                (5, 'EventLabels'),
                (6, 'Labels'),
                (7, 'Locations'),
                (8, 'Roles'),
                (9, 'RoleTickets'),
                (10, 'Tickets'),
                (11, 'EventUsers'),
                (12, 'EventTypeOwners'),
                (13, 'EventPrograms')

         SELECT * FROM @Results   

        -- Minden JĂ–VĹBELI PUBLIKUS esemĂ©ny, VAGY amihez a felhasznĂˇlĂłnak kĂ¶ze van (EventUser vagy Invitation)
        INSERT INTO @RelevantEvents (EventID, LocationID)
        SELECT DISTINCT e.id, e.EventLocationID
        FROM [EJ].[tblEvent] e
        LEFT JOIN [EJ].[tblEventUser] eu ON eu.EventID = e.id AND eu.UserID = @UserID AND eu.ActiveFlg = 1
        LEFT JOIN [EJ].[tblEventInvitation] ei ON ei.EventID = e.id AND ei.UserID = @UserID AND ei.ActiveFlg = 1
        WHERE e.ActiveFlg = 1 
          AND (
              (e.PublicFlg = 1 AND e.EndAtUtc >= GETUTCDATE()) -- Minden jĂ¶vĹ‘beli publikus
              OR (eu.id IS NOT NULL) -- Vagy rĂ©sztvevĹ‘/szervezĹ‘
              OR (ei.id IS NOT NULL) -- Vagy meghĂ­vott
          );

        -- RS 2: tblEvent (A szĹ±rt esemĂ©nyek)
        SELECT e.* 
        FROM [EJ].[tblEvent] e
        INNER JOIN @RelevantEvents re ON e.id = re.EventID;

        -- RS 3: tblEventInvitation (User sajĂˇt meghĂ­vĂłi)
        SELECT * 
        FROM [EJ].[tblEventInvitation] 
        WHERE UserID = @UserID AND ActiveFlg = 1;

        -- RS 4: tblEventLabel (CĂ­mke kapcsolĂłtĂˇbla a relevĂˇns esemĂ©nyekhez)
        SELECT el.* 
        FROM [EJ].[tblEventLabel] el
        INNER JOIN @RelevantEvents re ON el.EventID = re.EventID;

        -- RS 5: tblLabel (Az Ă¶sszes lĂ©tezĹ‘ cĂ­mke tĂ¶rzsadatkĂ©nt a keresĹ‘hĂ¶z)
        SELECT * 
        FROM [EJ].[tblLabel] 
        WHERE ActiveFlg = 1;

        -- RS 6: tblEventLocation (Csak a megjelenĂ­tett esemĂ©nyek helyszĂ­nei)
        SELECT loc.* 
        FROM [EJ].[tblEventLocation] loc
        WHERE loc.id IN (SELECT DISTINCT LocationID FROM @RelevantEvents WHERE LocationID IS NOT NULL)
          AND loc.ActiveFlg = 1;

        -- RS 7: tblEventRole (SzerepkĂ¶rĂ¶k a relevĂˇns esemĂ©nyekhez)
        SELECT er.* 
        FROM [EJ].[tblEventRole] er
        INNER JOIN @RelevantEvents re ON er.EventID = re.EventID
        WHERE er.ActiveFlg = 1;

        -- RS 8: tblEventRoleTicket
        -- INNER JOIN kell az EventRole-ra, hogy csak a kigyĹ±jtĂ¶tt esemĂ©nyekhez hĂşzzuk be
        SELECT ert.* 
        FROM [EJ].[tblEventRoleTicket] ert
        INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id
        INNER JOIN @RelevantEvents re ON er.EventID = re.EventID
        WHERE ert.ActiveFlg = 1 AND er.ActiveFlg = 1;

        -- RS 9: tblEventTicket (Jegy tĂ­pusok)
        SELECT et.* 
        FROM [EJ].[tblEventTicket] et
        INNER JOIN @RelevantEvents re ON et.EventID = re.EventID
        WHERE et.ActiveFlg = 1;

        -- RS 10: tblEventUser (A usert Ă©rintĹ‘ rĂ©szvĂ©telek)
        SELECT * 
        FROM [EJ].[tblEventUser] 
        WHERE UserID = @UserID AND ActiveFlg = 1;

        -- RS 11: tblEventTypeOwner (Szervezeti hovatartozĂˇs, pl. kinek a kĂ¶zĂ¶ssĂ©gei)
        SELECT * 
        FROM [EJ].[tblEventTypeOwner] 
        WHERE UserID = @UserID AND ActiveFlg = 1;

        -- RS 12: tblEventProgram
        SELECT ep.id, ep.EventID, ep.ProgramDateTime, ep.ProgramName, ep.ActiveFlg
        FROM [EJ].[tblEventProgram] ep
        INNER JOIN @RelevantEvents re ON ep.EventID = re.EventID
        WHERE ep.ActiveFlg = 1
        ORDER BY ep.ProgramDateTime ASC;

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
        
        -- Hiba esetĂ©n csak az elsĹ‘ Result Set megy vissza (Error stĂˇtusszal)
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    END CATCH
END


