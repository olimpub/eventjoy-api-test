const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

// Add TempId to CREATE TABLE #IncomingQuestions
content = content.replace(/CREATE TABLE #IncomingQuestions \(/, 'CREATE TABLE #IncomingQuestions (\n              TempId INT IDENTITY(1,1) PRIMARY KEY,');

// Modify the MERGE to output TempId instead of RowIndex
content = content.replace(/OUTPUT source\.RowIndex, inserted\.id INTO @InsertedQuestions;/, 'OUTPUT source.TempId, inserted.id INTO @InsertedQuestions;');

// Modify the UPDATE to join on TempId
content = content.replace(/JOIN @InsertedQuestions q ON i\.RowIndex = q\.RowIndex;/, 'JOIN @InsertedQuestions q ON i.TempId = q.TempId;');

// Also, the @InsertedQuestions table needs to have TempId instead of RowIndex
content = content.replace(/DECLARE @InsertedQuestions TABLE \(RowIndex INT, InsertedID INT\);/, 'DECLARE @InsertedQuestions TABLE (TempId INT, InsertedID INT);');

fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
