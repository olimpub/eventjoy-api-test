const mssql = require('mssql');
const fs = require('fs');

async function run() {
    const pool = await mssql.connect('Server=tcp:pulsator-prod.database.windows.net,1433;Initial Catalog=eventjoy-test;Persist Security Info=False;User ID=pulsator_root;Password=8sHFdrCp7u;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;');
    const result = await pool.request().query("SELECT OBJECT_DEFINITION(OBJECT_ID('[OP].[spSaveQuestion]')) AS Code");
    let code = result.recordset[0].Code;
    
    code = code.replace(/CREATE\s+PROCEDURE/i, 'CREATE OR ALTER PROCEDURE');
    code = `SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n` + code;
    
    code = code.replace(
        /-- 2\. Update tblQuestion[\s\n]*UPDATE \[OP\]\.\[tblQuestion\][\s\n]*SET Prompt = @NewPrompt,[\s\n]*TimeSec = @NewTimeSec,[\s\n]*LastCreatedUserID = @UserID[\s\n]*WHERE id = @QuestionID;/,
        `-- 2. Update tblQuestion
        UPDATE [OP].[tblQuestion]
        SET Prompt = @NewPrompt,
            TimeSec = @NewTimeSec,
            LastCreatedUserID = @UserID
        WHERE id = @QuestionID;
        
        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'ImageKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET ImageKey = JSON_VALUE(@Json, '$.ImageKey') WHERE id = @QuestionID;
        END

        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'AudioKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET AudioKey = JSON_VALUE(@Json, '$.AudioKey') WHERE id = @QuestionID;
        END
`
    );
    
    fs.writeFileSync('update_spSaveQuestion.sql', code, 'utf8');
    pool.close();
}
run();
