const fs = require('fs');
let code = fs.readFileSync('OlimpubEndpoints.cs', 'utf8');
const newEndpoint = `
        [Function("ImportOlimpubQuestions")]
        public async Task<HttpResponseData> ImportOlimpubQuestions([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/questions/import")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                if (string.IsNullOrWhiteSpace(requestBody))
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Hiányzó kérés törzs.");
                    return badReq;
                }

                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";

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
                    ReturnDescription = returnDescription
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ImportOlimpubQuestions error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
`;
code = code.replace(/    }\r?\n}/, newEndpoint + '    }\n}');
fs.writeFileSync('OlimpubEndpoints.cs', code, 'utf8');
