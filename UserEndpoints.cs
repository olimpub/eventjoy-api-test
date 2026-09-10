using System;
using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class UserEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public UserEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<UserEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        // =========================================================================
        // ADO.NET HELPER FĂśGGVĂ‰NY A RESULT SET-EK BEOLVASĂSĂHOZ
        // =========================================================================
        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                list.Add(row);
            }
            return list;
        }

        [Function("GetUserData")]
        public async Task<HttpResponseData> GetUserData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "user/data")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                _logger.LogWarning("Unauthorized access attempt to GetUserData.");
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetUserData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        int returnValue = 0;
                        string returnDescription = string.Empty;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            // 1. Result Set (Ăllapot)
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            var dynamicResults = new Dictionary<string, object?>();

                            // 2. RS: ResultList (a nevek listĂˇja)
                            var resultNames = new List<string>();
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var rsName = reader.FieldCount > 1 ? reader.GetValue(1)?.ToString() : reader.GetValue(0)?.ToString();
                                    if (!string.IsNullOrEmpty(rsName))
                                    {
                                        resultNames.Add(rsName);
                                    }
                                }
                            }

                            // A tovĂˇbbi result set-ek beolvasĂˇsa a kapott nevek alapjĂˇn
                            int nameIndex = 0;
                            if (resultNames.Count > 0 && resultNames[0].Equals("ReturnStatus", StringComparison.OrdinalIgnoreCase))
                            {
                                nameIndex = 2;
                            }

                            while (await reader.NextResultAsync())
                            {
                                var rsData = await ReadResultSetAsync(reader);
                                
                                string currentName;
                                if (nameIndex < resultNames.Count)
                                {
                                    currentName = resultNames[nameIndex];
                                }
                                else
                                {
                                    currentName = $"ExtraResultSet_{nameIndex + 1}";
                                }

                                // Egyedi objektumok kezelĂ©se (amelyeknĂ©l nem listĂˇt vĂˇr a frontend)
                                if (currentName.Equals("User", StringComparison.OrdinalIgnoreCase) ||
                                    currentName.Equals("Settings", StringComparison.OrdinalIgnoreCase) ||
                                    currentName.Equals("BillingAddress", StringComparison.OrdinalIgnoreCase))
                                {
                                    dynamicResults[currentName] = rsData.FirstOrDefault();
                                }
                                else if (currentName.Equals("MasterDataVersion", StringComparison.OrdinalIgnoreCase))
                                {
                                    var versionRow = rsData.FirstOrDefault();
                                    if (versionRow != null && versionRow.ContainsKey("MasterDataVersion"))
                                    {
                                        dynamicResults[currentName] = versionRow["MasterDataVersion"];
                                    }
                                    else
                                    {
                                        dynamicResults[currentName] = 0;
                                    }
                                }
                                else
                                {
                                    dynamicResults[currentName] = rsData;
                                }

                                nameIndex++;
                            }

                            // VISSZAKĂśLDĂ‰S A FRONTENDNEK
                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(dynamicResults);
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching user data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
        [Function("SaveUser")]
        public async Task<HttpResponseData> SaveUser([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "user/save")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                _logger.LogWarning("Unauthorized access attempt to SaveUser.");
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var data = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(requestBody);
                
                string firstName = data.TryGetProperty("FirstName", out var fnProp) ? fnProp.GetString() ?? "" : "";
                string lastName = data.TryGetProperty("LastName", out var lnProp) ? lnProp.GetString() ?? "" : "";

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spSaveUser]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@FirstName", firstName);
                        cmd.Parameters.AddWithValue("@LastName", lastName);

                        int returnValue = 0;
                        string returnDescription = string.Empty;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving user data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}

