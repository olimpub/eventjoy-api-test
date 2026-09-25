const fs = require('fs');
let content = fs.readFileSync('EmailRouterFunction.cs', 'utf8');

// Megkeressük a hibás sorokat és beletesszük az errorBody-t az Exception message-be
content = content.replace(
    /throw new Exception\(\$"MailerSend error: \{response\.StatusCode\}"\);/g,
    'throw new Exception($"MailerSend error: {response.StatusCode} - {errorBody}");'
);

fs.writeFileSync('EmailRouterFunction.cs', content, 'utf8');
