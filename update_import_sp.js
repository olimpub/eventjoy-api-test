const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

content = content.replace(/INSERT \(TopicID, QuestionTypeID, Prompt, TimeSec, MediaUrl, ActiveFlg, CreatedAtUtc\)/g, 'INSERT (TopicID, QuestionTypeID, Prompt, TimeSec, MediaUrl, ActiveFlg, CreatedAtUtc, LastCreatedUserID)');
content = content.replace(/VALUES \(source\.TopicID, source\.QuestionTypeID, source\.Prompt, ISNULL\(source\.TimeSec, 0\), source\.MediaUrl, 1, @Now\)/g, 'VALUES (source.TopicID, source.QuestionTypeID, source.Prompt, ISNULL(source.TimeSec, 0), source.MediaUrl, 1, @Now, @UserID)');

content = content.replace(/INSERT INTO \[OP\]\.\[tblRound\] \(EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg\)/g, 'INSERT INTO [OP].[tblRound] (EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg, LastCreatedUserID)');
content = content.replace(/@MaxSortIndex \+ ROW_NUMBER\(\) OVER \(ORDER BY MIN\(TempId\)\), \n\s*1\n\s*FROM #IncomingQuestions/g, '@MaxSortIndex + ROW_NUMBER() OVER (ORDER BY MIN(TempId)), \n              1, @UserID\n          FROM #IncomingQuestions');

content = content.replace(/INSERT INTO \[OP\]\.\[tblEventQuestion\] \(EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg\)/g, 'INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg, LastCreatedUserID)');
content = content.replace(/SELECT @EventID, RoundID, NewQuestionID, RN, 'pending', ISNULL\(TimeSec, 30\), 1\n\s*FROM RankedQuestions/g, "SELECT @EventID, RoundID, NewQuestionID, RN, 'pending', ISNULL(TimeSec, 30), 1, @UserID\n        FROM RankedQuestions");

fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
