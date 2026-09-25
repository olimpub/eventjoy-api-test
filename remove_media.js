const fs = require('fs');
let content = fs.readFileSync('add_auditing.sql', 'utf8');

// Remove tblMedia blocks
content = content.replace(/-- OP\.Media[\s\S]*?GO\s*/g, '');
content = content.replace(/CREATE OR ALTER TRIGGER \[OP\]\.\[trg_Media_Update\][\s\S]*?END\s*GO/g, '');

fs.writeFileSync('add_auditing.sql', content, 'utf8');
