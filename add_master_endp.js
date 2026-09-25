const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

const newFunc = `
        [Function("GetOlimpubMasterData")]
        public async Task<HttpResponseData> GetMasterData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/master")] HttpRequestData req)
        {
            // Ezt hívja meg a wizard, JWT kell
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);

            try
            {
                var responseDict = new Dictionary<string, object?>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    
                    // OpKabalas
                    using (var cmd = new SqlCommand("SELECT id, Name, ImageUrl, ActiveFlg FROM [OP].[tblKabala] WHERE ActiveFlg = 1", conn))
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        responseDict["OpKabalas"] = await ReadResultSetAsync(reader);
                    }

                    // OpTopics
                    using (var cmd = new SqlCommand("SELECT id, Name, ActiveFlg FROM [OP].[tblTopic] WHERE ActiveFlg = 1", conn))
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        responseDict["OpTopics"] = await ReadResultSetAsync(reader);
                    }
                }

                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await res.WriteAsJsonAsync(responseDict);
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubMasterData error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }
`;

content = content.replace(/    }\r?\n}/, newFunc + '    }\n}');
fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
