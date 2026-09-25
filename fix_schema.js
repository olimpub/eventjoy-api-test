const fs = require('fs');
let code = fs.readFileSync('SQL\\Migrations\\001_Olimpub_Schema.sql', 'utf8');

code = code.replace(
    /INSERT INTO \[EJ\]\.\[tblLoginIdentifierType\] \(id, Name, Code, Description, CreatedAtUtc, UpdatedAtUtc, ActiveFlg\)\r?\n\s*VALUES \(@NewID, 'Device', 'device', 'App\/Eszköz alapú belépés \(Olimpub ideiglenes user\)', SYSDATETIMEOFFSET\(\), SYSDATETIMEOFFSET\(\), 1\);/,
    `INSERT INTO [EJ].[tblLoginIdentifierType] (id, Name, Code, createdAt, ActiveFlg)
    VALUES (@NewID, 'Device', 'device', SYSDATETIMEOFFSET(), 1);`
);

fs.writeFileSync('SQL\\Migrations\\001_Olimpub_Schema.sql', code, 'utf8');
console.log('Fixed');
