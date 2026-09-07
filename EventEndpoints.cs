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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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

                            // 2. RS: ResultList (a nevek listája)
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

                            // A további result set-ek beolvasása a kapott nevek alapján
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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

                            // 2. RS: ResultList (a nevek listája)
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

                            // A további result set-ek beolvasása a kapott nevek alapján
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
                                    // Ha inaktív vagy nem Meghívott státuszban van, akkor "already_accepted" (vagy lejárt/elutasított)
                                    nextStep = "already_accepted";
                                }
                                else
                                {
                                    // Session ellenőrzése
                                    int? sessionUserId = null;
                                    try
                                    {
                                        sessionUserId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
                                    }
                                    catch
                                    {
                                        // Nem kötelező a token, így a hiba esetén null marad
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
                await badReqRes.WriteStringAsync("Érvénytelen UID formátum!");
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

                            // 2. RS: ResultList (a nevek listája)
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

                            // A további result set-ek beolvasása a kapott nevek alapján
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
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
                                batchId = reader["BatchID"] != DBNull.Value ? Guid.Parse(reader["BatchID"].ToString()) : null;
                            }
                            
                            var rows = new List<Dictionary<string, object>>();
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var row = new Dictionary<string, object>();
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
                                if (_serviceBusClient != null)
                                {
                                    await using var sender = _serviceBusClient.CreateSender("communication");
                                    var payload = new { MailId = batchId.Value };
                                    var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(payload))
                                    {
                                        MessageId = batchId.Value.ToString()
                                    };
                                    sbMessage.ApplicationProperties["channel"] = "email";
                                    await sender.SendMessageAsync(sbMessage);
                                    _logger.LogInformation($"Successfully published BatchID {batchId.Value} to ServiceBus.");
                                }
                                else
                                {
                                    _logger.LogWarning("ServiceBusConnection is missing. Could not publish BatchID messages.");
                                }
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
    }
}
