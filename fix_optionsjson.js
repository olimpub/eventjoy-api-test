const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spGetEventData.sql', 'utf8');

// Ensure OptionsJson includes the id!
content = content.replace(/SELECT ListType, Value, SortIndex/, 'SELECT id, ListType, Value, SortIndex');

fs.writeFileSync('SQL\\Procedures\\OP.spGetEventData.sql', content, 'utf8');
