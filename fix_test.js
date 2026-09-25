const fs = require('fs');
let content = fs.readFileSync('SQL\\test_olimpub.sql', 'utf8');

content = content.replace(
    /INSERT INTO \[EJ\]\.\[tblEvent\][^;]+;/s,
    "INSERT INTO [EJ].[tblEvent] (Title, Description, EventStatusID, EventTypeID, StartAtUtc, EndAtUtc, CreatedByUserID)\nVALUES ('Teszt Olimpub Esemény', 'Olimpub teszt', 1, 43, SYSDATETIME(), SYSDATETIME(), 1);"
);

fs.writeFileSync('SQL\\test_olimpub.sql', content, 'utf8');
