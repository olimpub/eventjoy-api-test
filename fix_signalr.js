const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spChangeGame.sql', 'utf8');

// The pattern is: ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @<something>Payload);
content = content.replace(/_gamer',\s*@Action,\s*@(.*?)Payload\);/g, `_gamer', @Action, @$1Payload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @$1Payload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @$1Payload);`);

// Wait, PublishRound has a different pattern:
// ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, (SELECT ... FOR JSON PATH))
content = content.replace(/'_gamer',\s*@Action,\s*\(\s*SELECT @EventID AS EventID.*?FOR JSON PATH, WITHOUT_ARRAY_WRAPPER\s*\)\s*\);/s, match => {
    return match.replace(/_gamer',\s*@Action,\s*\(/, `_gamer', @Action, (`)
    .slice(0, -2) + `),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, (SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, JSON_QUERY((SELECT @RoundID AS RoundID, 'active' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, (SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, JSON_QUERY((SELECT @RoundID AS RoundID, 'active' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));`;
});

fs.writeFileSync('SQL\\Procedures\\OP.spChangeGame.sql', content, 'utf8');
