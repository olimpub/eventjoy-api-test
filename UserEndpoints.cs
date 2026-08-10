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
                ?? throw new InvalidOperationException("JwtSecret app setting is missing.");
        }

        // =========================================================================
        // ADO.NET HELPER FÜGGVÉNY A RESULT SET-EK BEOLVASÁSÁHOZ
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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
                            // 1. Result Set (Állapot)
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

                            // Dinamikus változók az összes adatnak
                            object? user = null, settings = null, billingAddress = null, masterDataVersion = 0;
                            List<Dictionary<string, object?>> notifications = new(), chatThreads = new(), eventTypePrefs = new(), labelPrefs = new(), loginIdentifiers = new();

                            // 2. RS: tblUser
                            if (await reader.NextResultAsync()) user = (await ReadResultSetAsync(reader)).FirstOrDefault();
                            
                            // 3. RS: tblNotification
                            if (await reader.NextResultAsync()) notifications = await ReadResultSetAsync(reader);

                            // 4. RS: tblChatThreadUser
                            if (await reader.NextResultAsync()) chatThreads = await ReadResultSetAsync(reader);

                            // 5. RS: tblUserEventTypePreference
                            if (await reader.NextResultAsync()) eventTypePrefs = await ReadResultSetAsync(reader);

                            // 6. RS: tblUserLabelPreference
                            if (await reader.NextResultAsync()) labelPrefs = await ReadResultSetAsync(reader);

                            // 7. RS: tblUserSettings
                            if (await reader.NextResultAsync()) settings = (await ReadResultSetAsync(reader)).FirstOrDefault();

                            // 8. RS: tblUserLoginIdentifier
                            if (await reader.NextResultAsync()) loginIdentifiers = await ReadResultSetAsync(reader);

                            // 9. RS: tblUserBillingAddress
                            if (await reader.NextResultAsync()) billingAddress = (await ReadResultSetAsync(reader)).FirstOrDefault();

                            // 10. RS: tblDataVersion
                            if (await reader.NextResultAsync())
                            {
                                var versionRow = (await ReadResultSetAsync(reader)).FirstOrDefault();
                                if (versionRow != null && versionRow.ContainsKey("MasterDataVersion"))
                                {
                                    masterDataVersion = versionRow["MasterDataVersion"];
                                }
                            }

                            // VISSZAKÜLDÉS A FRONTENDNEK
                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new
                            {
                                User = user,
                                Notifications = notifications,
                                ChatThreads = chatThreads,
                                EventTypePreferences = eventTypePrefs,
                                LabelPreferences = labelPrefs,
                                Settings = settings,
                                LoginIdentifiers = loginIdentifiers,
                                BillingAddress = billingAddress,
                                MasterDataVersion = masterDataVersion
                            });
                            
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
    }
}
