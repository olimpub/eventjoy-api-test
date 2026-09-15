using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;

using System.IO;
using Newtonsoft.Json;
using System.Data;
using System.Collections.Generic;
using System;

namespace EventJoy.Api
{
    public class PtaEndpoints
    {
        private readonly string _sqlConnectionString;
        private readonly string _jwtSecret;

        public PtaEndpoints(IConfiguration configuration)
        {
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
            _jwtSecret = configuration["JwtSecret"] ?? string.Empty;
        }

        [Function("CreateDisplayToken")]
        public async Task<HttpResponseData> CreateDisplayToken([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "pta/display-token")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var response = req.CreateResponse(HttpStatusCode.Unauthorized);
                return response;
            }

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic? data = JsonConvert.DeserializeObject(requestBody);
            
            if (data == null || data!.EventID == null)
            {
                var response = req.CreateResponse(HttpStatusCode.BadRequest);
                return response;
            }

            int eventId = (int)data!.EventID;

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();

                using (var cmd = new SqlCommand("[PTA].[spCreateDisplayToken]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@EventID", eventId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            string retDesc = reader.GetString(reader.GetOrdinal("ReturnDescription"));

                            if (retVal != 1)
                            {
                                var errorRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                return errorRes;
                            }

                            var result = new
                            {
                                ReturnValue = retVal,
                                EventID = reader.GetInt32(reader.GetOrdinal("EventID")),
                                Pin = reader.GetString(reader.GetOrdinal("Pin")),
                                Token = reader.GetString(reader.GetOrdinal("Token")),
                                ExpiresAtUtc = reader.GetDateTimeOffset(reader.GetOrdinal("ExpiresAtUtc")),
                                Url = $"/profitability/event/{eventId}/display"
                            };

                            var res = req.CreateResponse(HttpStatusCode.OK);
                            await res.WriteAsJsonAsync(result);
                            return res;
                        }
                    }
                }
            }

            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }

        [Function("ValidateDisplaySession")]
        public async Task<HttpResponseData> ValidateDisplaySession([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "pta/display-session")] HttpRequestData req)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic? data = JsonConvert.DeserializeObject(requestBody);

            if (data == null || (data!.EventID == null && data!.EventUID == null) || data!.Pin == null)
            {
                return req.CreateResponse(HttpStatusCode.BadRequest);
            }

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();

                using (var cmd = new SqlCommand("[PTA].[spValidateDisplaySession]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    if (data!.EventID != null) cmd.Parameters.AddWithValue("@EventID", (int)data!.EventID);
                    if (data!.EventUID != null) cmd.Parameters.AddWithValue("@EventUID", (Guid)data!.EventUID);
                    cmd.Parameters.AddWithValue("@Pin", (string)data!.Pin);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1)
                            {
                                var errorRes = req.CreateResponse(HttpStatusCode.Forbidden);
                                await errorRes.WriteStringAsync(reader.GetString(reader.GetOrdinal("ReturnDescription")));
                                return errorRes;
                            }

                            var result = new
                            {
                                ReturnValue = retVal,
                                EventID = reader.GetInt32(reader.GetOrdinal("EventID")),
                                Token = reader.GetString(reader.GetOrdinal("Token")),
                                ExpiresAtUtc = reader.GetDateTimeOffset(reader.GetOrdinal("ExpiresAtUtc"))
                            };

                            var res = req.CreateResponse(HttpStatusCode.OK);
                            await res.WriteAsJsonAsync(result);
                            return res;
                        }
                    }
                }
            }

            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }
        
        [Function("GetEventDisplayData")]
        public async Task<HttpResponseData> GetEventDisplayData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "pta/display/{eventId}")] HttpRequestData req, int eventId)
        {
            // Auth can be Bearer {user JWT}, Bearer {DisplayToken}, or X-Pta-Display-Token: {DisplayToken}
            bool isAuthorized = false;
            
            // 1. Try Display Token (Header)
            string? displayToken = null;
            if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues))
            {
                displayToken = System.Linq.Enumerable.FirstOrDefault(headerValues);
            }
            
            // 2. Try Bearer
            if (string.IsNullOrEmpty(displayToken) && req.Headers.TryGetValues("Authorization", out var authValues))
            {
                string? authHeader = System.Linq.Enumerable.FirstOrDefault(authValues);
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                {
                    string potentialToken = authHeader!.Substring("Bearer ".Length).Trim();
                    
                    // Try as JWT first
                    int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
                    if (userId != null)
                    {
                        // Check if user is Organizer/QM on this EventID
                        using (var connAuth = new SqlConnection(_sqlConnectionString))
                        {
                            await connAuth.OpenAsync();
                            var authCmd = new SqlCommand("SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND r.RoleTypeID IN (1, 2)", connAuth);
                            authCmd.Parameters.AddWithValue("@EventID", eventId);
                            authCmd.Parameters.AddWithValue("@UserID", userId.Value);
                            var scalar = await authCmd.ExecuteScalarAsync();
                            if (scalar != null)
                            {
                                isAuthorized = true;
                            }
                        }
                    }
                    else
                    {
                        // Maybe it's a DisplayToken
                        displayToken = potentialToken;
                    }
                }
            }
            
            // Validate Display Token if present
            if (!isAuthorized && !string.IsNullOrEmpty(displayToken))
            {
                using (var connToken = new SqlConnection(_sqlConnectionString))
                {
                    await connToken.OpenAsync();
                    var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE EventID = @EventID AND Token = @Token AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", connToken);
                    tokenCmd.Parameters.AddWithValue("@EventID", eventId);
                    tokenCmd.Parameters.AddWithValue("@Token", displayToken);
                    var scalar = await tokenCmd.ExecuteScalarAsync();
                    if (scalar != null)
                    {
                        isAuthorized = true;
                    }
                }
            }
            
            if (!isAuthorized)
            {
                var errorRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await errorRes.WriteStringAsync("A kivetítés lejárt.");
                return errorRes;
            }

            // Fetch the data
                        var response = req.CreateResponse(HttpStatusCode.OK);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();

                using (var cmd = new SqlCommand("[PTA].[spGetEventDisplayData]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@EventID", eventId);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            string retDesc = reader.GetString(reader.GetOrdinal("ReturnDescription"));

                            if (retVal != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(retDesc);
                                return errRes;
                            }
                        }

                        var dynamicResults = new Dictionary<string, object?>();
                        var resultNames = new List<string>();

                        // RS 2: ResultList
                        if (await reader.NextResultAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                string? rsName = reader.FieldCount > 1 ? reader.GetValue(1)?.ToString() : reader.GetValue(0)?.ToString();
                                if (!string.IsNullOrEmpty(rsName))
                                {
                                    resultNames.Add(rsName);
                                }
                            }
                        }

                        int nameIndex = 2; // Because RS 1 and 2 are already consumed

                        while (await reader.NextResultAsync())
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

                            string currentName;
                            if (nameIndex < resultNames.Count)
                            {
                                currentName = resultNames[nameIndex];
                            }
                            else
                            {
                                currentName = $"ExtraResultSet_{nameIndex + 1}";
                            }

                            if (currentName == "PtaDisplayState" && list.Count > 0)
                            {
                                dynamicResults[currentName] = list[0]; // Object, not array
                            }
                            else
                            {
                                dynamicResults[currentName] = list; // Array
                            }
                            
                            nameIndex++;
                        }

                        await response.WriteAsJsonAsync(dynamicResults);
                        return response;
                    }
                }
            }
        }

        [Function("GetEventRoundAvailableStatuses")]
        public async Task<HttpResponseData> GetEventRoundAvailableStatuses([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "pta/rounds/{roundId}/available-statuses")] HttpRequestData req, int roundId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            var response = req.CreateResponse(HttpStatusCode.OK);
            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[PTA].[spGetEventRoundAvailableStatuses]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@EventRoundID", roundId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(reader.GetString(reader.GetOrdinal("ReturnDescription")));
                                return errRes;
                            }

                            var result = new Dictionary<string, object>
                            {
                                { "currentStatusId", reader.GetInt32(reader.GetOrdinal("CurrentStatusID")) },
                                { "canUndoCurrent", reader.GetBoolean(reader.GetOrdinal("CanUndoCurrent")) }
                            };

                            if (await reader.NextResultAsync() && await reader.ReadAsync()) // Skip ResultName
                            { }
                            
                            if (await reader.NextResultAsync())
                            {
                                var availableStatuses = new List<object>();
                                while (await reader.ReadAsync())
                                {
                                    availableStatuses.Add(new
                                    {
                                        statusId = reader.GetInt32(reader.GetOrdinal("StatusID")),
                                        statusName = reader.GetString(reader.GetOrdinal("StatusName"))
                                    });
                                }
                                result["availableNextStatuses"] = availableStatuses;
                            }

                            await response.WriteAsJsonAsync(result);
                            return response;
                        }
                    }
                }
            }
            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }

        [Function("UpdateEventRoundStatus")]
        public async Task<HttpResponseData> UpdateEventRoundStatus([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "pta/rounds/{roundId}/status")] HttpRequestData req, int roundId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic? data = JsonConvert.DeserializeObject(requestBody);
            if (data == null || data!.newStatusId == null) return req.CreateResponse(HttpStatusCode.BadRequest);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[PTA].[spUpdateEventRoundStatus]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@EventRoundID", roundId);
                    cmd.Parameters.AddWithValue("@NewStatusID", (int)data!.newStatusId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null && (int)result == 1)
                    {
                        return req.CreateResponse(HttpStatusCode.OK);
                    }
                }
            }
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        [Function("RollbackEventRoundStatus")]
        public async Task<HttpResponseData> RollbackEventRoundStatus([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "pta/rounds/{roundId}/status/rollback")] HttpRequestData req, int roundId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[PTA].[spRollbackEventRoundStatus]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@EventRoundID", roundId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null && (int)result == 1)
                    {
                        return req.CreateResponse(HttpStatusCode.OK);
                    }
                }
            }
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }
    }
}
