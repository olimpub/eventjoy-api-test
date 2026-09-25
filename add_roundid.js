const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const returnStatement = `          COMMIT TRANSACTION;
          
          DECLARE @FirstRoundID INT = (SELECT TOP 1 RoundID FROM @CreatedRounds);
          
          SELECT 
              1 AS ReturnValue, 
              N'Sikeres importálás (' + CAST((SELECT COUNT(*) FROM #IncomingQuestions) AS NVARCHAR(20)) + ' db kérdés).' AS ReturnDescription,
              @FirstRoundID AS RoundID;`;

content = content.replace(/COMMIT TRANSACTION;\s*SELECT 1 AS ReturnValue.*?AS ReturnDescription;/, returnStatement);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
