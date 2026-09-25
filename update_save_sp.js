const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spSaveQuestion.sql', 'utf8');

content = content.replace(/SET Prompt = @NewPrompt,[\s\S]*?TimeSec = @NewTimeSec/g, 'SET Prompt = @NewPrompt,\n            TimeSec = @NewTimeSec,\n            LastCreatedUserID = @UserID');
content = content.replace(/SET TimeSec = @NewTimeSec,[\s\S]*?SortIndex = ISNULL\(@NewSortIndex, SortIndex\)/g, 'SET TimeSec = @NewTimeSec,\n            SortIndex = ISNULL(@NewSortIndex, SortIndex),\n            LastCreatedUserID = @UserID');

fs.writeFileSync('SQL\\Procedures\\OP.spSaveQuestion.sql', content, 'utf8');
