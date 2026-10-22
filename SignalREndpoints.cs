using System;
using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class SignalREndpoints
    {
        private readonly ILogger _logger;
        private readonly string _sqlConnectionString;
        private readonly string _jwtSecret;
        private readonly Azure.Messaging.ServiceBus.ServiceBusClient? _serviceBusClient;

        public SignalREndpoints(
            ILoggerFactory loggerFactory,
            Microsoft.Extensions.Configuration.IConfiguration configuration,
            IServiceProvider serviceProvider)
        {
            _logger = loggerFactory.CreateLogger<SignalREndpoints>();
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
            _jwtSecret = configuration["JwtSecret"] ?? string.Empty;
            _serviceBusClient = serviceProvider.GetService<Azure.Messaging.ServiceBus.ServiceBusClient>();
        }

        [Function("negotiate")]
        public async Task<HttpResponseData> Negotiate(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequestData req,
            [SignalRConnectionInfoInput(HubName = "eventHub", ConnectionStringSetting = "AzureSignalRConnectionString")] string connectionInfo)
        {
            _logger.LogInformation("SignalR negotiate requested.");
            
            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "application/json");
            await response.WriteStringAsync(connectionInfo);
            
            return response;
        }

        public class JoinGroupRequest
        {
            public string ConnectionId { get; set; } = string.Empty;
            public System.Collections.Generic.List<string> GroupNames { get; set; } = new System.Collections.Generic.List<string>();
        }

        public class SignalRJoinOutput
        {
            [SignalROutput(HubName = "eventHub", ConnectionStringSetting = "AzureSignalRConnectionString")]
            public SignalRGroupAction[] Actions { get; set; } = Array.Empty<SignalRGroupAction>();

            [HttpResult]
            public HttpResponseData HttpResponse { get; set; } = default!;
        }

        [Function("joinGroup")]
        public async Task<SignalRJoinOutput> JoinGroup(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "signalr/join")] HttpRequestData req)
        {
            _logger.LogInformation("SignalR joinGroup requested.");
            var body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var payload = System.Text.Json.JsonSerializer.Deserialize<JoinGroupRequest>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            
            if (payload == null || string.IsNullOrEmpty(payload.ConnectionId) || payload.GroupNames == null || payload.GroupNames.Count == 0)
            {
                _logger.LogWarning("Invalid joinGroup payload.");
                return new SignalRJoinOutput { HttpResponse = req.CreateResponse(HttpStatusCode.BadRequest) };
            }

            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            // 1. Try Display Token (from X-Pta-Display-Token header or Authorization: Bearer <DisplayToken>)
            string? displayToken = null;
            if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues))
            {
                displayToken = System.Linq.Enumerable.FirstOrDefault(headerValues);
            }
            else if (userId == null && req.Headers.TryGetValues("Authorization", out var authValues))
            {
                var authHeader = System.Linq.Enumerable.FirstOrDefault(authValues);
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", System.StringComparison.OrdinalIgnoreCase))
                {
                    displayToken = authHeader.Substring("Bearer ".Length).Trim();
                }
            }
            
            int? authorizedDisplayEventId = null;
            if (!string.IsNullOrEmpty(displayToken))
            {
                using (var connToken = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                {
                    await connToken.OpenAsync();
                    var tokenCmd = new Microsoft.Data.SqlClient.SqlCommand("SELECT EventID FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", connToken);
                    tokenCmd.Parameters.AddWithValue("@Token", displayToken);
                    var scalar = await tokenCmd.ExecuteScalarAsync();
                    if (scalar != null && scalar != System.DBNull.Value)
                    {
                        authorizedDisplayEventId = System.Convert.ToInt32(scalar);
                    }
                }
            }

            var authorizedStaffEventIds = new System.Collections.Generic.HashSet<int>();
            var gamerEventIds = new System.Collections.Generic.HashSet<int>();

            foreach (var group in payload.GroupNames)
            {
                if (string.IsNullOrEmpty(group)) continue;
                
                // If it's a TV with display-token, it MUST NOT join gamer/organizer/user groups
                if (!string.IsNullOrEmpty(displayToken) && userId == null)
                {
                    if (group.EndsWith("_gamer") || group.EndsWith("_organizer") || group.EndsWith("_contributor") || group.EndsWith("_gamemaster") || group.EndsWith("_qm") || group.EndsWith("_participant") || group.Contains("_user_"))
                    {
                        _logger.LogWarning("TV tried to join restricted group.");
                        return new SignalRJoinOutput { HttpResponse = req.CreateResponse(HttpStatusCode.Forbidden) };
                    }
                }

                if (group.StartsWith("event_") && group.EndsWith("_gamer") && userId.HasValue)
                {
                    var parts = group.Split('_');
                    if (parts.Length >= 3 && int.TryParse(parts[1], out int gamerEventId))
                    {
                        gamerEventIds.Add(gamerEventId);
                    }
                }

                if (group.StartsWith("event_") && group.EndsWith("_display"))
                {
                    var parts = group.Split('_');
                    if (parts.Length >= 3 && int.TryParse(parts[1], out int eventId))
                    {
                        if (authorizedDisplayEventId.HasValue && authorizedDisplayEventId.Value == eventId)
                        {
                            // Authorized by display token
                            continue;
                        }
                        
                        if (userId.HasValue)
                        {
                            if (!authorizedStaffEventIds.Contains(eventId))
                            {
                                using (var connAuth = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                                {
                                    await connAuth.OpenAsync();
                                    var authCmd = new Microsoft.Data.SqlClient.SqlCommand("SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND (r.RoleTypeID IN (1, 2) OR r.id = 7)", connAuth);
                                    authCmd.Parameters.AddWithValue("@EventID", eventId);
                                    authCmd.Parameters.AddWithValue("@UserID", userId.Value);
                                    if (await authCmd.ExecuteScalarAsync() != null)
                                    {
                                        authorizedStaffEventIds.Add(eventId);
                                    }
                                }
                            }

                            if (authorizedStaffEventIds.Contains(eventId))
                            {
                                // Authorized by JWT Staff
                                continue;
                            }
                        }
                        
                        // Not authorized for display group
                        return new SignalRJoinOutput { HttpResponse = req.CreateResponse(HttpStatusCode.Forbidden) };
                    }
                }
            }

            // Update Olimpub player presence (LastSeenUtc) when joining event_{id}_gamer
            if (userId.HasValue && gamerEventIds.Count > 0)
            {
                foreach (var gamerEventId in gamerEventIds)
                {
                    try
                    {
                        long? eventUserId = null;
                        int? teamId = null;
                        bool wasOnline = true;
                        long stateVersion = 0;

                        using (var connPresence = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                        {
                            await connPresence.OpenAsync();
                            const string presenceSql = @"
DECLARE @Now DATETIME2 = SYSUTCDATETIME();
DECLARE @EventUserID BIGINT = NULL;
DECLARE @TeamID INT = NULL;
DECLARE @WasOnline BIT = 0;
DECLARE @StateVersion BIGINT = 0;

SELECT TOP 1
    @EventUserID = tm.EventUserID,
    @TeamID = tm.TeamID,
    @WasOnline = CASE WHEN tm.LastSeenUtc IS NOT NULL AND tm.LastSeenUtc >= DATEADD(MINUTE, -3, @Now) THEN 1 ELSE 0 END
FROM [OP].[tblTeamMember] tm
JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
JOIN [EJ].[tblEventUser] eu ON tm.EventUserID = eu.id
WHERE t.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND tm.ActiveFlg = 1 AND t.ActiveFlg = 1;

IF @EventUserID IS NOT NULL
BEGIN
    UPDATE [OP].[tblTeamMember]
    SET LastSeenUtc = @Now
    WHERE TeamID = @TeamID AND EventUserID = @EventUserID AND ActiveFlg = 1
      AND (LastSeenUtc IS NULL OR LastSeenUtc < DATEADD(SECOND, -60, @Now));
END

SELECT @StateVersion = ISNULL(StateVersion, 0) FROM [OP].[tblEventSettings] WHERE EventID = @EventID;
SELECT @EventUserID AS EventUserID, @TeamID AS TeamID, @WasOnline AS WasOnline, ISNULL(@StateVersion, 0) AS StateVersion;";

                            using (var presenceCmd = new Microsoft.Data.SqlClient.SqlCommand(presenceSql, connPresence))
                            {
                                presenceCmd.Parameters.AddWithValue("@EventID", gamerEventId);
                                presenceCmd.Parameters.AddWithValue("@UserID", userId.Value);

                                using (var reader = await presenceCmd.ExecuteReaderAsync())
                                {
                                    if (await reader.ReadAsync() && !reader.IsDBNull(0) && !reader.IsDBNull(1))
                                    {
                                        eventUserId = Convert.ToInt64(reader.GetValue(0));
                                        teamId = Convert.ToInt32(reader.GetValue(1));
                                        wasOnline = Convert.ToBoolean(reader.GetValue(2));
                                        stateVersion = Convert.ToInt64(reader.GetValue(3));
                                    }
                                }
                            }
                        }

                        // Emit Op.Presence ping only on state transition (offline -> online)
                        if (eventUserId.HasValue && teamId.HasValue && !wasOnline && _serviceBusClient != null)
                        {
                            await using var sender = _serviceBusClient.CreateSender("communication");
                            var presencePayload = new
                            {
                                Action = "Op.Presence",
                                EventID = gamerEventId,
                                EventUserID = eventUserId.Value,
                                TeamID = teamId.Value,
                                Online = true,
                                StateVersion = stateVersion,
                                Payload = new
                                {
                                    EventUserID = eventUserId.Value,
                                    TeamID = teamId.Value,
                                    Online = true,
                                    StateVersion = stateVersion
                                }
                            };

                            var targetGroups = new[]
                            {
                                $"event_{gamerEventId}_organizer",
                                $"event_{gamerEventId}_gamemaster",
                                $"event_{gamerEventId}_display"
                            };

                            var messages = new System.Collections.Generic.List<Azure.Messaging.ServiceBus.ServiceBusMessage>();
                            foreach (var tg in targetGroups)
                            {
                                var sbPayload = new
                                {
                                    TargetGroup = tg,
                                    EventName = "Op.Presence",
                                    PayloadJson = presencePayload
                                };
                                var sbMsg = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(sbPayload))
                                {
                                    MessageId = Guid.NewGuid().ToString()
                                };
                                sbMsg.ApplicationProperties["channel"] = "signalr";
                                messages.Add(sbMsg);
                            }

                            await sender.SendMessagesAsync(messages);
                            _logger.LogInformation($"Published Op.Presence (online=true) for EventUserID={eventUserId.Value}, TeamID={teamId.Value} on EventID={gamerEventId}.");
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, $"Failed to update Olimpub presence for EventID={gamerEventId}, UserID={userId.Value}.");
                    }
                }
            }

            var actions = new System.Collections.Generic.List<SignalRGroupAction>();
            foreach (var group in payload.GroupNames)
            {
                if (!string.IsNullOrEmpty(group))
                {
                    actions.Add(new SignalRGroupAction(SignalRGroupActionType.Add)
                    {
                        ConnectionId = payload.ConnectionId,
                        GroupName = group
                    });

                    // Live gameplay backward comp and role mapping
                    if (group.EndsWith("_contributor"))
                    {
                        actions.Add(new SignalRGroupAction(SignalRGroupActionType.Add)
                        {
                            ConnectionId = payload.ConnectionId,
                            GroupName = group.Replace("_contributor", "_gamemaster")
                        });
                    }
                    if (group.EndsWith("_organizer"))
                    {
                        actions.Add(new SignalRGroupAction(SignalRGroupActionType.Add)
                        {
                            ConnectionId = payload.ConnectionId,
                            GroupName = group.Replace("_organizer", "_gamemaster")
                        });
                    }
                    if (group.EndsWith("_qm"))
                    {
                        actions.Add(new SignalRGroupAction(SignalRGroupActionType.Add)
                        {
                            ConnectionId = payload.ConnectionId,
                            GroupName = group.Replace("_qm", "_gamemaster")
                        });
                    }
                }
            }

            return new SignalRJoinOutput { Actions = actions.ToArray(), HttpResponse = req.CreateResponse(HttpStatusCode.OK) };
        }
    }
}
