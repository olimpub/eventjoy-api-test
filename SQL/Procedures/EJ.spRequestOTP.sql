SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO



    
    ALTER PROCEDURE [EJ].[spRequestOTP]
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
    
        -- BiztonsĂˇgi ellenĹ‘rzĂ©s: ha egyiket sem adtĂˇk meg
        IF (@EmailAddress IS NULL AND @PhoneNumber IS NULL)
        BEGIN
            SELECT -1 AS ReturnValue, N'HiĂˇnyzĂł Email Ă©s TelefonszĂˇm!' AS ReturnDescription
            RETURN;
        END
    
        BEGIN TRY
            -- 1. GenerĂˇlunk egy 6-jegyĹ± kĂłdot (100000 - 999999 kĂ¶zĂ¶tt)
            SET @GeneratedCode = CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(10))
            
            -- 2. Ă‰rvĂ©nyessĂ©gi idĹ‘ beĂˇllĂ­tĂˇsa (5 perc mĂşlva lejĂˇr)
            SET @ValidUntil = DATEADD(minute, 5, SYSDATETIMEOFFSET())
    
            -- 3. EllenĹ‘rizzĂĽk, lĂ©tezik-e mĂˇr a felhasznĂˇlĂł
            SELECT TOP 1 @UserID = id FROM [EJ].[tblUser] 
            WHERE (EmailAddress = @EmailAddress AND @EmailAddress IS NOT NULL)
               OR (PhoneNumber = @PhoneNumber AND @PhoneNumber IS NOT NULL)

            IF (@UserID IS NULL)
            BEGIN
                -- Ha nem talĂˇlhatĂł felhasznĂˇlĂł, ellenĹ‘rizzĂĽk a tblUserLoginIdentifier tĂˇblĂˇt
                SELECT TOP 1 @UserID = le.UserID 
                FROM [EJ].[tblUserLoginIdentifier] le 
                WHERE le.IdentifierValueNormalized = @EmailAddress OR le.IdentifierValueNormalized = @PhoneNumber;
            END
    
            IF (@UserID IS NOT NULL)
            BEGIN
                -- LĂ©tezĹ‘ felhasznĂˇlĂł -> FrissĂ­tjĂĽk a kĂłdjĂˇt a tĂˇblĂˇban
                UPDATE [EJ].[tblUser]
                SET ValidationCode = @GeneratedCode,
                    ValidationCodeExpiry = @ValidUntil,
                    LastUpdatedUserID = @UserID,
                    updatedAt = SYSDATETIMEOFFSET()
                WHERE id = @UserID;
            END
            ELSE
            BEGIN
                -- Ăšj felhasznĂˇlĂł -> RegisztrĂˇljuk 'FĂĽggĹ‘ben' (1) stĂˇtusszal, kĂłd mentĂ©sĂ©vel
                INSERT INTO [EJ].[tblUser] (EmailAddress, PhoneNumber, StatusID, ValidationCode, ValidationCodeExpiry)
                VALUES (@EmailAddress, @PhoneNumber, 1, @GeneratedCode, @ValidUntil)
    
                -- LekĂ©rjĂĽk az Ăşjonnan beszĂşrt ID-t
                SET @UserID = SCOPE_IDENTITY()
                UPDATE [EJ].[tblUser] SET LastUpdatedUserID = @UserID WHERE id = @UserID;
            END

            --Email kĂĽldĂ©s vagy SMS kĂĽldĂ©s logikĂˇja itt tĂ¶rtĂ©nhetne, de a MailerSend API hĂ­vĂˇs a C# backendben tĂ¶rtĂ©nik majd, ezĂ©rt itt csak az adatokat adjuk vissza.
            IF(@EmailAddress IS NOT NULL) --tehĂˇt email kĂĽldĂ©s esetĂ©n
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

                 -- SMS kĂĽldĂ©s logikĂˇja itt tĂ¶rtĂ©nhetne, de a tĂ©nyleges SMS kĂĽldĂ©s a C# backendben tĂ¶rtĂ©nik majd, ezĂ©rt itt csak az adatokat adjuk vissza.
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
                           ,N'EventJoy belĂ©pĂ©si kĂłd:' +@GeneratedCode   --<Message, nvarchar(500),>
                           ,GETDATE()--<createdAt, datetimeoffset(7),>
                           ,0--<StatusID, smallint,>

                 SELECT @SMSOutboxID=SCOPE_IDENTITY()
           
            END

    
            -- Minden sikeres volt
            SET @ReturnValue = 1
            SET @ReturnDescription = 'Success'
    
            -- RESULT SET 1 (Alap visszatĂ©rĂ©si Ă©rtĂ©kek a C#-nak)
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription, @BatchID AS MailID, @SMSOutboxID AS SMSID
            
            -- RESULT SET 2 (Csak ha sikeres volt!)
            -- Ezt az adathalmazt hasznĂˇlja majd fel a C# arra, hogy kikĂĽldje a MailerSend API-val az emailt!
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


