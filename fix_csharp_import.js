const fs = require('fs');
let content = fs.readFileSync('OlimpubEndpoints.cs', 'utf8');

const importReplacement = `                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";
                int? roundId = null;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spImportQuestions]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Json", requestBody);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                if (reader.FieldCount > 2 && reader["RoundID"] != DBNull.Value)
                                {
                                    roundId = Convert.ToInt32(reader["RoundID"]);
                                }
                            }
                        }
                    }
                }

                if (returnValue != 1)
                {
                    var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await errorRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                    return errorRes;
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    ReturnDescription = returnDescription,
                    RoundID = roundId
                });

                return response;`;

content = content.replace(/int returnValue = -1;[\s\S]*?return response;/g, match => {
    // Only replace the one in ImportOlimpubQuestions
    if (match.includes('[OP].[spImportQuestions]')) {
        return importReplacement;
    }
    return match;
});

fs.writeFileSync('OlimpubEndpoints.cs', content, 'utf8');
