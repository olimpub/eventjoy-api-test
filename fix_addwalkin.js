const fs = require('fs');
let sql = fs.readFileSync('sp_addwalkin.sql', 'utf8');

// Remove header rows (up to the first row of dashes)
let lines = sql.split('\n');
let startIndex = 0;
for(let i=0; i<lines.length; i++) {
    if(lines[i].includes('CREATE   PROCEDURE') || lines[i].includes('CREATE PROCEDURE')) {
        startIndex = i;
        break;
    }
}
let cleanSql = lines.slice(startIndex).join('\n');
cleanSql = cleanSql.replace(/CREATE\s+PROCEDURE/g, 'CREATE OR ALTER PROCEDURE');
cleanSql = `SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n` + cleanSql;

fs.writeFileSync('update_addwalkin.sql', cleanSql, 'utf8');
