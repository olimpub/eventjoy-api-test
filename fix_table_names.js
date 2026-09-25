const fs = require('fs');
let content = fs.readFileSync('add_auditing.sql', 'utf8');

content = content.replace(/\[OP\]\.\[Kabala\]/g, '[OP].[tblKabala]');
content = content.replace(/\[OP\]\.\[Topic\]/g, '[OP].[tblTopic]');
content = content.replace(/\[OP\]\.\[Question\]/g, '[OP].[tblQuestion]');
content = content.replace(/\[OP\]\.\[EventSettings\]/g, '[OP].[tblEventSettings]');
content = content.replace(/\[OP\]\.\[Team\]/g, '[OP].[tblTeam]');
content = content.replace(/\[OP\]\.\[Round\]/g, '[OP].[tblRound]');
content = content.replace(/\[OP\]\.\[EventQuestion\]/g, '[OP].[tblEventQuestion]');
content = content.replace(/\[OP\]\.\[Penalty\]/g, '[OP].[tblPenalty]');
content = content.replace(/\[OP\]\.\[Media\]/g, '[OP].[tblMedia]'); // wait, tblMedia?

fs.writeFileSync('add_auditing.sql', content, 'utf8');
