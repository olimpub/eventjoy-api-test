const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

content = content.replace(
    /\/\/\s*In real EventJoy there's a tblEventDisplayToken table, assuming it's valid\s*isDisplay = true;/,
    `using (var tokenConn = new SqlConnection(_connectionString)) {
        await tokenConn.OpenAsync();
        using (var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND EventID = @EventID AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", tokenConn)) {
            tokenCmd.Parameters.AddWithValue("@Token", token);
            tokenCmd.Parameters.AddWithValue("@EventID", id);
            if (await tokenCmd.ExecuteScalarAsync() != null) {
                isDisplay = true;
            }
        }
    }`
);

// Also fix in GetLeaderboard
content = content.replace(
    /if \(req\.Headers\.TryGetValues\("X-Pta-Display-Token", out var headerValues\) && !string\.IsNullOrEmpty\(headerValues\.FirstOrDefault\(\)\)\)\s*{\s*isDisplay = true;\s*}/,
    `if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues)) {
        var token = headerValues.FirstOrDefault();
        if (!string.IsNullOrEmpty(token)) {
            using (var tokenConn = new SqlConnection(_connectionString)) {
                await tokenConn.OpenAsync();
                using (var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND EventID = @EventID AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", tokenConn)) {
                    tokenCmd.Parameters.AddWithValue("@Token", token);
                    tokenCmd.Parameters.AddWithValue("@EventID", id);
                    if (await tokenCmd.ExecuteScalarAsync() != null) {
                        isDisplay = true;
                    }
                }
            }
        }
    }`
);

fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
