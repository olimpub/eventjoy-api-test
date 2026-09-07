

CREATE PROCEDURE [EJ].[spSaveRefreshToken]
        @UserId INT,
        @TokenHash NVARCHAR(256),
        @DeviceId NVARCHAR(256),
        @DeviceName NVARCHAR(256),
        @ExpiresAt DATETIMEOFFSET(7)
    AS
    BEGIN
         SET NOCOUNT ON;

        DECLARE 	
            @ReturnValue INT,
            @ReturnDescription VARCHAR(MAX)

        BEGIN TRY
            -- A) Revokáljuk (érvénytelenítjük) a régebbi tokent, ha UGYANARRÓL a DeviceId-ról jött
            IF (@DeviceId IS NOT NULL AND @DeviceId != '')
            BEGIN
                UPDATE [EJ].[tblRefreshToken]
                SET RevokedAt = SYSDATETIMEOFFSET()
                WHERE UserId = @UserId 
                  AND DeviceId = @DeviceId 
                  AND RevokedAt IS NULL;
            END
    
            -- B) MAXIMUM 5 AKTÍV ESZKÖZ SZABÁLY!
            -- Megnézzük, hány aktív tokenje van a usernek
            DECLARE @ActiveCount INT;
            SELECT @ActiveCount = COUNT(*) FROM [EJ].[tblRefreshToken] 
            WHERE UserId = @UserId AND RevokedAt IS NULL AND ExpiresAt > SYSDATETIMEOFFSET();
    
            -- Ha már van 5 (vagy több) aktív eszköze, a legrégebbit visszavonjuk
            IF (@ActiveCount >= 5)
            BEGIN
                UPDATE [EJ].[tblRefreshToken]
                SET RevokedAt = SYSDATETIMEOFFSET()
                WHERE id IN (
                    SELECT TOP 1 id 
                    FROM [EJ].[tblRefreshToken] 
                    WHERE UserId = @UserId AND RevokedAt IS NULL AND ExpiresAt > SYSDATETIMEOFFSET()
                    ORDER BY createdAt ASC -- A legrégebbit!
                );
            END
    
            -- C) BEMENTJÜK AZ ÚJ TOKENT
            INSERT INTO [EJ].[tblRefreshToken] (UserId, TokenHash, DeviceId, DeviceName, ExpiresAt, createdAt)
            VALUES (@UserId, @TokenHash, @DeviceId, @DeviceName, @ExpiresAt, SYSDATETIMEOFFSET());
    
        END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
    END CATCH

    -- Mindig visszaadja a standard API Result Setet
    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    END

