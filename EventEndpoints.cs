using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class EventEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;
        private readonly Azure.Messaging.ServiceBus.ServiceBusClient? _serviceBusClient;

        public EventEndpoints(ILoggerFactory loggerFactory, IServiceProvider serviceProvider)
        {
            _logger = loggerFactory.CreateLogger<EventEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
            _serviceBusClient = Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions.GetService<Azure.Messaging.ServiceBus.ServiceBusClient>(serviceProvider);
        }

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

        [Function("GetEventData")]
        public async Task<HttpResponseData> GetEventData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/data")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetEventData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

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

                                dynamicResults[currentName] = rsData;
                                nameIndex++;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(dynamicResults);
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching event data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetEventUserDataSheet")]
        public async Task<HttpResponseData> GetEventUserDataSheet([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/userdata/{eventUserId}")] HttpRequestData req, long eventUserId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetEventUserDataSheet]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventUserID", eventUserId);

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

                                dynamicResults[currentName] = rsData;
                                nameIndex++;
                            }

                            // Calculate NextStep logic
                            string nextStep = "enter_code";
                            var responseData = new Dictionary<string, object?>(dynamicResults);

                            if (dynamicResults.TryGetValue("InvitationData", out var invObj) && invObj is List<Dictionary<string, object?>> invList && invList.Count > 0)
                            {
                                var inv = invList[0];
                                int? statusId = inv.TryGetValue("EventUserStatusID", out var sId) && sId != null ? Convert.ToInt32(sId) : null;
                                int? invUserId = inv.TryGetValue("UserID", out var uId) && uId != null ? Convert.ToInt32(uId) : null;
                                bool isActive = inv.TryGetValue("ActiveFlg", out var aFlg) && aFlg != null ? Convert.ToBoolean(aFlg) : true;

                                if (!isActive || statusId != 1)
                                {
                                    // Ha inaktĂ­v vagy nem MeghĂ­vott stĂˇtuszban van, akkor "already_accepted" (vagy lejĂˇrt/elutasĂ­tott)
                                    nextStep = "already_accepted";
                                }
                                else
                                {
                                    // Session ellenĹ‘rzĂ©se
                                    int? sessionUserId = null;
                                    try
                                    {
                                        sessionUserId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
                                    }
                                    catch
                                    {
                                        // Nem kĂ¶telezĹ‘ a token, Ă­gy a hiba esetĂ©n null marad
                                    }

                                    if (sessionUserId.HasValue)
                                    {
                                        if (invUserId.HasValue && invUserId.Value != sessionUserId.Value)
                                        {
                                            nextStep = "account_conflict";
                                        }
                                        else
                                        {
                                            nextStep = "open_event";
                                        }
                                    }
                                    else
                                    {
                                        nextStep = "enter_code";
                                    }
                                }
                            }

                            responseData["NextStep"] = nextStep;

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(responseData);
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching event user datasheet.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetInvitationByUid")]
        public async Task<HttpResponseData> GetInvitationByUid([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "invite/{uid}")] HttpRequestData req, string uid)
        {
            if (!Guid.TryParse(uid, out Guid parsedUid))
            {
                var badReqRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badReqRes.WriteStringAsync("Ă‰rvĂ©nytelen UID formĂˇtum!");
                return badReqRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetInvitationByUid]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UID", parsedUid);

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

                                dynamicResults[currentName] = rsData;
                                nameIndex++;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(dynamicResults);
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching invitation data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
        [Function("SaveEvent")]
        public async Task<HttpResponseData> SaveEvent([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/save")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spSaveEvent]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        int? newEventId = null;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                newEventId = reader["EventID"] != DBNull.Value ? Convert.ToInt32(reader["EventID"]) : null;
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new { 
                                ReturnValue = returnValue, 
                                ReturnDescription = returnDescription,
                                EventID = newEventId
                            });
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving event.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message} | StackTrace: {ex.StackTrace}");
                return errorRes;
            }
        }

        [Function("ChangeEvent")]
        public async Task<HttpResponseData> ChangeEvent([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/change")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spChangeEvent]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        int? newEventId = null;
                        string action = string.Empty;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                newEventId = reader["EventID"] != DBNull.Value ? Convert.ToInt32(reader["EventID"]) : null;
                                action = reader["Action"]?.ToString() ?? string.Empty;
                            }
                            
                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new { 
                                ReturnValue = returnValue, 
                                ReturnDescription = returnDescription,
                                EventID = newEventId,
                                Action = action
                            });

                            if (returnValue == 1 && await reader.NextResultAsync())
                            {
                                if (_serviceBusClient != null)
                                {
                                    await using var sender = _serviceBusClient.CreateSender("communication");
                                    var messages = new System.Collections.Generic.List<Azure.Messaging.ServiceBus.ServiceBusMessage>();

                                    while (await reader.ReadAsync())
                                    {
                                        var targetGroup = reader["TargetGroup"]?.ToString();
                                        var eventName = reader["EventName"]?.ToString();
                                        var payloadJson = reader["PayloadJson"]?.ToString();

                                        if (!string.IsNullOrEmpty(targetGroup) && !string.IsNullOrEmpty(eventName) && !string.IsNullOrEmpty(payloadJson))
                                        {
                                            var sbPayload = new { TargetGroup = targetGroup, EventName = eventName, PayloadJson = System.Text.Json.JsonSerializer.Deserialize<object>(payloadJson) };
                                            var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(sbPayload))
                                            {
                                                MessageId = Guid.NewGuid().ToString()
                                            };
                                            sbMessage.ApplicationProperties["channel"] = "signalr";
                                            messages.Add(sbMessage);
                                        }
                                    }

                                    if (messages.Count > 0)
                                    {
                                        await sender.SendMessagesAsync(messages);
                                        _logger.LogInformation($"Successfully published {messages.Count} messages to ServiceBus as a batch.");
                                    }
                                }
                            }

                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error changing event.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message} | StackTrace: {ex.StackTrace}");
                return errorRes;
            }
        }

        [Function("SaveEventContent")]
        public async Task<HttpResponseData> SaveEventContent([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/content/save")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spSaveEventContent]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        int? newEventId = null;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                newEventId = reader["EventID"] != DBNull.Value ? Convert.ToInt32(reader["EventID"]) : null;
                            }
                            
                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new { 
                                ReturnValue = returnValue, 
                                ReturnDescription = returnDescription,
                                EventID = newEventId
                            });
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving event content.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message} | StackTrace: {ex.StackTrace}");
                return errorRes;
            }
        }

        [Function("ImportInvitations")]
        public async Task<HttpResponseData> ImportInvitations([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/invite/import")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Ă‰rvĂ©nytelen vagy lejĂˇrt bejelentkezĂ©si token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spImportInvitations]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        int? newEventId = null;
                        Guid? batchId = null;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                newEventId = reader["EventID"] != DBNull.Value ? Convert.ToInt32(reader["EventID"]) : null;
                                batchId = reader["BatchID"] != DBNull.Value ? Guid.Parse(reader["BatchID"].ToString()!) : null;
                            }
                            
                            var rows = new List<Dictionary<string, object?>>();
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var row = new Dictionary<string, object?>();
                                    for (int i = 0; i < reader.FieldCount; i++)
                                    {
                                        row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    }
                                    rows.Add(row);
                                }
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteAsJsonAsync(new {
                                    ReturnValue = returnValue,
                                    ReturnDescription = returnDescription,
                                    EventID = newEventId,
                                    BatchID = batchId,
                                    Rows = rows
                                });
                                return errRes;
                            }
                            if (batchId != null)
                            {
                                // HACK: Kikerült az E-mail ServiceBus beküldés, mert Timer kezeli.
                                _logger.LogInformation($"BatchID {batchId.Value} created successfully (waiting for Timer pickup).");
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new { 
                                ReturnValue = returnValue, 
                                ReturnDescription = returnDescription,
                                EventID = newEventId,
                                BatchID = batchId,
                                Rows = rows
                            });
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error importing invitations.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message} | StackTrace: {ex.StackTrace}");
                return errorRes;
            }
        }
        [Function("AddWalkinParticipant")]
        public async Task<HttpResponseData> AddWalkinParticipant([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/invite/walkin")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var dto = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(requestBody);
                
                long eventId = dto.GetProperty("EventID").GetInt64();
                string? firstName = dto.TryGetProperty("FirstName", out var fn) ? fn.GetString() : null;
                string? lastName = dto.TryGetProperty("LastName", out var ln) ? ln.GetString() : null;
                string? email = dto.TryGetProperty("Email", out var em) ? em.GetString() : null;
                string? phone = dto.TryGetProperty("Phone", out var ph) ? ph.GetString() : null;
                string? organizationName = dto.TryGetProperty("OrganizationName", out var org) ? org.GetString() : null;
                string? teamName = dto.TryGetProperty("TeamName", out var tm) ? tm.GetString() : null;
                string? regionName = dto.TryGetProperty("RegionName", out var rg) ? rg.GetString() : null;
                string? companyName = dto.TryGetProperty("CompanyName", out var cp) ? cp.GetString() : null;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spAddWalkinParticipant]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", eventId);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@FirstName", (object?)firstName ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@LastName", (object?)lastName ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@Email", (object?)email ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@Phone", (object?)phone ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@OrganizationName", (object?)organizationName ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@TeamName", (object?)teamName ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@RegionName", (object?)regionName ?? DBNull.Value);
                        cmd.Parameters.AddWithValue("@CompanyName", (object?)companyName ?? DBNull.Value);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        long? eventUserId = null;
                        Guid? batchId = null;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                eventUserId = reader["EventUserID"] != DBNull.Value ? Convert.ToInt64(reader["EventUserID"]) : null;
                                if (reader.FieldCount > 3)
                                {
                                    batchId = reader["BatchID"] != DBNull.Value ? Guid.Parse(reader["BatchID"].ToString()!) : null;
                                }
                            }
                        }

                        if (returnValue == 400)
                        {
                            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                            await badReq.WriteStringAsync(returnDescription);
                            return badReq;
                        }
                        if (returnValue == 403)
                        {
                            var forbid = req.CreateResponse(HttpStatusCode.Forbidden);
                            await forbid.WriteStringAsync(returnDescription);
                            return forbid;
                        }
                        if (returnValue == 409)
                        {
                            var confReq = req.CreateResponse(HttpStatusCode.Conflict);
                            await confReq.WriteStringAsync(returnDescription);
                            return confReq;
                        }
                        if (returnValue != 0)
                        {
                            var serverErr = req.CreateResponse(HttpStatusCode.InternalServerError);
                            await serverErr.WriteStringAsync(returnDescription);
                            return serverErr;
                        }

                        // HACK: Kikerült az E-mail ServiceBus beküldés, mert Timer kezeli.

                        var response = req.CreateResponse(HttpStatusCode.OK);
                        await response.WriteAsJsonAsync(new
                        {
                            ReturnValue = returnValue,
                            ReturnDescription = returnDescription,
                            EventUserID = eventUserId
                        });
                        return response;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in AddWalkinParticipant.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message}");
                return errorRes;
            }
        }
        [Function("GetEventJoinInfo")]
        public async Task<HttpResponseData> GetEventJoinInfo([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/join/{eventUid}")] HttpRequestData req, string eventUid)
        {
            try
            {
                if (!Guid.TryParse(eventUid, out var uid))
                {
                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badRes.WriteStringAsync("Érvénytelen EventUID.");
                    return badRes;
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetEventJoinInfo]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventUID", uid);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                string returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;

                                if (returnValue == 404)
                                {
                                    var notFound = req.CreateResponse(HttpStatusCode.NotFound);
                                    await notFound.WriteStringAsync(returnDescription);
                                    return notFound;
                                }

                                var response = req.CreateResponse(HttpStatusCode.OK);
                                await response.WriteAsJsonAsync(new
                                {
                                    EventUID = reader["EventUID"],
                                    EventID = reader["EventID"],
                                    Title = reader["Title"],
                                    CheckInOpen = Convert.ToBoolean(reader["CheckInOpen"]),
                                    EventStatusName = reader["EventStatusName"]?.ToString() ?? string.Empty
                                });
                                return response;
                            }
                        }
                    }
                }
                
                var err = req.CreateResponse(HttpStatusCode.InternalServerError);
                await err.WriteStringAsync("Ismeretlen hiba.");
                return err;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting event join info.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message}");
                return errorRes;
            }
        }

        [Function("JoinEvent")]
        public async Task<HttpResponseData> JoinEvent([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/join")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var dto = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(requestBody);
                
                string? eventUidStr = dto.TryGetProperty("EventUID", out var uidProp) ? uidProp.GetString() : null;
                if (string.IsNullOrEmpty(eventUidStr) || !Guid.TryParse(eventUidStr, out var eventUid))
                {
                    var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Érvénytelen vagy hiányzó EventUID.");
                    return badReq;
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spJoinEvent]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventUID", eventUid);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        int returnValue = 0;
                        string returnDescription = string.Empty;
                        long? eventId = null;
                        long? eventUserId = null;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                eventId = reader["EventID"] != DBNull.Value ? Convert.ToInt64(reader["EventID"]) : null;
                                eventUserId = reader["EventUserID"] != DBNull.Value ? Convert.ToInt64(reader["EventUserID"]) : null;
                            }
                        }

                        if (returnValue == 400)
                        {
                            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                            await badReq.WriteStringAsync(returnDescription);
                            return badReq;
                        }
                        if (returnValue == 404)
                        {
                            var notFound = req.CreateResponse(HttpStatusCode.NotFound);
                            await notFound.WriteStringAsync(returnDescription);
                            return notFound;
                        }
                        if (returnValue != 0)
                        {
                            var serverErr = req.CreateResponse(HttpStatusCode.InternalServerError);
                            await serverErr.WriteStringAsync(returnDescription);
                            return serverErr;
                        }

                        var response = req.CreateResponse(HttpStatusCode.OK);
                        await response.WriteAsJsonAsync(new
                        {
                            ReturnValue = returnValue,
                            ReturnDescription = returnDescription,
                            EventID = eventId,
                            EventUserID = eventUserId
                        });
                        return response;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in JoinEvent.");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteStringAsync($"Error: {ex.Message}");
                return errorRes;
            }
        }
    }
}



