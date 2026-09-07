


    
    CREATE PROCEDURE [EJ].[spRequestOTP]
        @EmailAddress NVARCHAR(300) = NULL,
        @PhoneNumber NVARCHAR(50) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
    
        DECLARE     
            @ReturnValue INT,
            @ReturnDescription VARCHAR(MAX),
            @UserID INT,
            @GeneratedCode NVARCHAR(10),
            @ValidUntil DATETIMEOFFSET(7),
            @EmailOutboxID INT,
            @SMSOutboxID INT
    
        -- Biztonsági ellenőrzés: ha egyiket sem adták meg
        IF (@EmailAddress IS NULL AND @PhoneNumber IS NULL)
        BEGIN
            SELECT -1 AS ReturnValue, N'Hiányzó Email és Telefonszám!' AS ReturnDescription
            RETURN;
        END
    
        BEGIN TRY
            -- 1. Generálunk egy 6-jegyű kódot (100000 - 999999 között)
            SET @GeneratedCode = CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(10))
            
            -- 2. Érvényességi idő beállítása (5 perc múlva lejár)
            SET @ValidUntil = DATEADD(minute, 5, SYSDATETIMEOFFSET())
    
            -- 3. Ellenőrizzük, létezik-e már a felhasználó
            SELECT TOP 1 @UserID = id FROM [EJ].[tblUser] 
            WHERE (EmailAddress = @EmailAddress AND @EmailAddress IS NOT NULL)
               OR (PhoneNumber = @PhoneNumber AND @PhoneNumber IS NOT NULL)

            IF (@UserID IS NULL)
            BEGIN
                -- Ha nem található felhasználó, ellenőrizzük a tblUserLoginIdentifier táblát
                SELECT TOP 1 @UserID = le.UserID 
                FROM [EJ].[tblUserLoginIdentifier] le 
                WHERE le.IdentifierValueNormalized = @EmailAddress OR le.IdentifierValueNormalized = @PhoneNumber;
            END
    
            IF (@UserID IS NOT NULL)
            BEGIN
                -- Létező felhasználó -> Frissítjük a kódját a táblában
                UPDATE [EJ].[tblUser]
                SET ValidationCode = @GeneratedCode,
                    ValidationCodeExpiry = @ValidUntil,
                    updatedAt = SYSDATETIMEOFFSET()
                WHERE id = @UserID;
            END
            ELSE
            BEGIN
                -- Új felhasználó -> Regisztráljuk 'Függőben' (1) státusszal, kód mentésével
                INSERT INTO [EJ].[tblUser] (EmailAddress, PhoneNumber, StatusID, ValidationCode, ValidationCodeExpiry)
                VALUES (@EmailAddress, @PhoneNumber, 1, @GeneratedCode, @ValidUntil)
    
                -- Lekérjük az újonnan beszúrt ID-t
                SET @UserID = SCOPE_IDENTITY()
            END

            --Email küldés vagy SMS küldés logikája itt történhetne, de a MailerSend API hívás a C# backendben történik majd, ezért itt csak az adatokat adjuk vissza.
            IF(@EmailAddress IS NOT NULL) --tehát email küldés esetén
            BEGIN
                
                DECLARE @BatchID UNIQUEIDENTIFIER = NEWID()

                INSERT INTO [EJ].[tblEmailOutbox]
                           ([BatchID]
                           ,[TemplateID]
                           ,[RefID]
                           ,[UserID]
                           ,[EmailName]
                           ,[EmailAddress]
                           ,[createdAt]
                           ,[StatusID]
                            )
                     VALUES
                           (@BatchID--<BatchID, uniqueidentifier,>
                           ,1--<TemplateID, int,>
                           ,@UserID--<RefID, int,>
                           ,@UserID--<UserID, int,>
                           ,''--<EmailName, nvarchar(150),>
                           ,@EmailAddress--<EmailAddress, nvarchar(300),>
                           ,GETDATE()--<createdAt, datetimeoffset(7),>
                           ,0--<StatusID, smallint,>
                           )
                    
                    SELECT @EmailOutboxID = SCOPE_IDENTITY()

                    INSERT INTO [EJ].[tblEmailOutboxParams]
                               ([EmailID]
                               ,[ParamName]
                               ,[ParamValue]
                               ,[LastUpdatedUserID]
                               ,[createdAt]
                               ,[updatedAt])
                     VALUES
                               (@EmailOutboxID--<EmailID, int,>
                               ,'EntryCode'--<ParamName, varchar(100),>
                               ,@GeneratedCode--<ParamValue, nvarchar(500),>
                               ,@UserID--<LastUpdatedUserID, int,>
                               ,GETDATE()--<createdAt, datetimeoffset(7),>
                               ,GETDATE()--<updatedAt, datetimeoffset(7),>)
                               )
            END
            ELSE
            BEGIN

                 -- SMS küldés logikája itt történhetne, de a tényleges SMS küldés a C# backendben történik majd, ezért itt csak az adatokat adjuk vissza.
                 INSERT INTO [EJ].[tblSMSOutbox]
                           ([SenderType]
                           ,[SenderName]
                           ,[RefID]
                           ,[UserID]
                           ,[PhoneNo]
                           ,[Message]
                           ,[createdAt]
                           ,[StatusID]
                    )
                     SELECT
                            'gText'--<SenderType, varchar(20),>
                           ,'EventJoyApp'--<SenderName, varchar(15),>
                           ,@UserID--<RefID, int,>
                           ,@UserID--<UserID, int,>
                           ,[EJ].[fnCleanPhoneNumber](@PhoneNumber) --<PhoneNo, varchar(30),>
                           ,N'EventJoy belépési kód:' +@GeneratedCode   --<Message, nvarchar(500),>
                           ,GETDATE()--<createdAt, datetimeoffset(7),>
                           ,0--<StatusID, smallint,>

                 SELECT @SMSOutboxID=SCOPE_IDENTITY()
           
            END

    
            -- Minden sikeres volt
            SET @ReturnValue = 1
            SET @ReturnDescription = 'Success'
    
            -- RESULT SET 1 (Alap visszatérési értékek a C#-nak)
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription, @BatchID AS MailID, @SMSOutboxID AS SMSID
            
            -- RESULT SET 2 (Csak ha sikeres volt!)
            -- Ezt az adathalmazt használja majd fel a C# arra, hogy kiküldje a MailerSend API-val az emailt!
            IF (@ReturnValue = 1)
            BEGIN
                SELECT 
                    @UserID AS UserID
            END
            
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END

