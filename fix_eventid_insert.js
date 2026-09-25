const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const updatedEventQuestionInsert = `        INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, ActiveFlg)
        SELECT @EventID, RoundID, NewQuestionID, RN, 1
        FROM RankedQuestions
        WHERE RN <= 8;`;

content = content.replace(/INSERT INTO \[OP\]\.\[tblEventQuestion\] \(RoundID, QuestionID, SortIndex, ActiveFlg\)\s*SELECT RoundID, NewQuestionID, RN, 1\s*FROM RankedQuestions\s*WHERE RN <= 8;/, updatedEventQuestionInsert);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
