const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

const newFunc = `
        [Function("GetOlimpubQuestions")]
        public async Task<HttpResponseData> GetQuestions([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/questions/{id}")] HttpRequestData req, long id)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);

            try
            {
                var rows = new List<Dictionary<string, object?>>();
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetRepositoryQuestions]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", id);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            rows = await ReadResultSetAsync(reader);
                        }
                    }
                }
                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await res.WriteAsJsonAsync(rows);
                return res;
            }
            catch (SqlException ex) when (ex.Number == 50060)
            {
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.Forbidden);
                await errRes.WriteAsJsonAsync(new { Error = ex.Message });
                return errRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubQuestions error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }
`;

content = content.replace(/    }\r?\n}/, newFunc + '    }\n}');
fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
