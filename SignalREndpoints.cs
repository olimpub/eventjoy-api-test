using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
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
            public List<string> GroupNames { get; set; } = new List<string>();
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
                displayToken = headerValues.FirstOrDefault();
            }
            else if (userId == null && req.Headers.TryGetValues("Authorization", out var authValues))
            {
                var authHeader = authValues.FirstOrDefault();
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                {
                    displayToken = authHeader.Substring("Bearer ".Length).Trim();
                }
            }
            
            int? authorizedDisplayEventId = null;
            int? authorizedDisplayId = null;
            if (!string.IsNullOrEmpty(displayToken))
            {
                using (var connToken = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                {
                    await connToken.OpenAsync();
                    var tokenCmd = new Microsoft.Data.SqlClient.SqlCommand(@"
                        SELECT id, EventID
                        FROM [PTA].[tblEventDisplayToken]
                        WHERE Token = @Token
                          AND ActiveFlg = 1
                          AND TokenActiveFlg = 1
                          AND ExpiresAtUtc > SYSUTCDATETIME()", connToken);
                    tokenCmd.Parameters.AddWithValue("@Token", displayToken);
                    using (var r = await tokenCmd.ExecuteReaderAsync())
                    {
                        if (await r.ReadAsync())
                        {
                            authorizedDisplayId = r.GetInt32(0);
                            authorizedDisplayEventId = r.GetInt32(1);
                        }
                    }
                }

                if (userId == null && !authorizedDisplayEventId.HasValue)
                {
                    return new SignalRJoinOutput { HttpResponse = req.CreateResponse(HttpStatusCode.Unauthorized) };
                }
            }

            var authorizedStaffEventIds = new HashSet<int>();
            var gamerEventIds = new HashSet<int>();
            var displayEventIds = new HashSet<int>();

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
                            displayEventIds.Add(eventId);
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
                                displayEventIds.Add(eventId);
                                continue;
                            }
                        }
                        
                        // Not authorized for display group -> 401 if no valid JWT/token
                        var statusCode = userId.HasValue ? HttpStatusCode.Forbidden : HttpStatusCode.Unauthorized;
                        return new SignalRJoinOutput { HttpResponse = req.CreateResponse(statusCode) };
                    }
                }
            }

            // Update Olimpub player presence (LastSeenUtc) and track connection when joining event_{id}_gamer
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
                        var otherConnIds = new List<string>();

                        using (var connPresence = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                        {
                            await connPresence.OpenAsync();
                            const string presenceSql = @"
DECLARE @Now DATETIME2 = SYSUTCDATETIME();
DECLARE @EventUserID BIGINT = NULL;
DECLARE @TeamID INT = NULL;
DECLARE @WasOnline BIT = 0;
DECLARE @StateVersion BIGINT = 0;

SELECT TOP 1 @EventUserID = eu.id
FROM [EJ].[tblEventUser] eu
WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1;

SELECT TOP 1
    @TeamID = tm.TeamID,
    @WasOnline = CASE WHEN tm.LastSeenUtc IS NOT NULL AND tm.LastSeenUtc >= DATEADD(MINUTE, -3, @Now) THEN 1 ELSE 0 END
FROM [OP].[tblTeamMember] tm
JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
WHERE t.EventID = @EventID AND tm.EventUserID = @EventUserID AND tm.ActiveFlg = 1 AND t.ActiveFlg = 1;

IF @EventUserID IS NOT NULL AND @TeamID IS NOT NULL
BEGIN
    UPDATE [OP].[tblTeamMember]
    SET LastSeenUtc = @Now
    WHERE TeamID = @TeamID AND EventUserID = @EventUserID AND ActiveFlg = 1
      AND (LastSeenUtc IS NULL OR LastSeenUtc < DATEADD(SECOND, -60, @Now));
END

IF @EventUserID IS NOT NULL AND OBJECT_ID('[OP].[tblClientConnection]', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM [OP].[tblClientConnection] WHERE EventID = @EventID AND ConnectionId = @ConnectionId AND RoleGroup = 'gamer')
    BEGIN
        UPDATE [OP].[tblClientConnection]
        SET UserID = @UserID, EventUserID = @EventUserID, LastSeenUtc = @Now, ActiveFlg = 1
        WHERE EventID = @EventID AND ConnectionId = @ConnectionId AND RoleGroup = 'gamer';
    END
    ELSE
    BEGIN
        INSERT INTO [OP].[tblClientConnection] (EventID, ConnectionId, RoleGroup, UserID, EventUserID, ConnectedAtUtc, LastSeenUtc, ActiveFlg)
        VALUES (@EventID, @ConnectionId, 'gamer', @UserID, @EventUserID, @Now, @Now, 1);
    END
END

SELECT @StateVersion = ISNULL(StateVersion, 0) FROM [OP].[tblEventSettings] WHERE EventID = @EventID;
SELECT @EventUserID AS EventUserID, @TeamID AS TeamID, @WasOnline AS WasOnline, ISNULL(@StateVersion, 0) AS StateVersion;

IF @EventUserID IS NOT NULL AND OBJECT_ID('[OP].[tblClientConnection]', 'U') IS NOT NULL
BEGIN
    SELECT ConnectionId
    FROM [OP].[tblClientConnection]
    WHERE EventID = @EventID AND RoleGroup = 'gamer' AND EventUserID = @EventUserID AND ActiveFlg = 1 AND ConnectionId != @ConnectionId;
END";

                            using (var presenceCmd = new Microsoft.Data.SqlClient.SqlCommand(presenceSql, connPresence))
                            {
                                presenceCmd.Parameters.AddWithValue("@EventID", gamerEventId);
                                presenceCmd.Parameters.AddWithValue("@UserID", userId.Value);
                                presenceCmd.Parameters.AddWithValue("@ConnectionId", payload.ConnectionId);

                                using (var reader = await presenceCmd.ExecuteReaderAsync())
                                {
                                    if (await reader.ReadAsync())
                                    {
                                        if (!reader.IsDBNull(0)) eventUserId = Convert.ToInt64(reader.GetValue(0));
                                        if (!reader.IsDBNull(1)) teamId = Convert.ToInt32(reader.GetValue(1));
                                        if (!reader.IsDBNull(2)) wasOnline = Convert.ToBoolean(reader.GetValue(2));
                                        if (!reader.IsDBNull(3)) stateVersion = Convert.ToInt64(reader.GetValue(3));
                                    }
                                    if (await reader.NextResultAsync())
                                    {
                                        while (await reader.ReadAsync())
                                        {
                                            if (!reader.IsDBNull(0)) otherConnIds.Add(reader.GetString(0));
                                        }
                                    }
                                }
                            }

                            if (otherConnIds.Count > 0)
                            {
                                var checks = await Task.WhenAll(otherConnIds.Select(async cid => (cid, alive: await SignalRManagementHelper.IsConnectionAliveAsync(cid))));
                                var deadIds = checks.Where(x => !x.alive).Select(x => x.cid).ToList();
                                if (deadIds.Count > 0)
                                {
                                    foreach (var deadId in deadIds)
                                    {
                                        using var delCmd = new Microsoft.Data.SqlClient.SqlCommand("UPDATE [OP].[tblClientConnection] SET ActiveFlg = 0 WHERE EventID = @EventID AND ConnectionId = @ConnectionId", connPresence);
                                        delCmd.Parameters.AddWithValue("@EventID", gamerEventId);
                                        delCmd.Parameters.AddWithValue("@ConnectionId", deadId);
                                        await delCmd.ExecuteNonQueryAsync();
                                    }
                                }
                            }
                        }

                        // Emit Op.Presence ping only on state transition (offline -> online)
                        if (eventUserId.HasValue && teamId.HasValue && !wasOnline && _serviceBusClient != null)
                        {
                            await using var sender = _serviceBusClient.CreateSender(Environment.GetEnvironmentVariable("CommunicationTopic") ?? "communication");
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

                            var messages = new List<Azure.Messaging.ServiceBus.ServiceBusMessage>();
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

                        await SignalRManagementHelper.TryPublishConnectionsChangedAsync(_serviceBusClient, gamerEventId, stateVersion);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, $"Failed to update Olimpub presence for EventID={gamerEventId}, UserID={userId.Value}.");
                    }
                }
            }

            // Track Olimpub display connections when joining event_{id}_display
            if (displayEventIds.Count > 0)
            {
                foreach (var dispEventId in displayEventIds)
                {
                    try
                    {
                        var otherDispConns = new List<string>();
                        long stateVersion = 0;

                        using (var connDisp = new Microsoft.Data.SqlClient.SqlConnection(_sqlConnectionString))
                        {
                            await connDisp.OpenAsync();
                            const string dispSql = @"
DECLARE @Now DATETIME2 = SYSUTCDATETIME();
DECLARE @ResolvedDisplayID INT = @DisplayID;
DECLARE @StateVersion BIGINT = 0;

IF @ResolvedDisplayID IS NOT NULL
BEGIN
    UPDATE [PTA].[tblEventDisplayToken]
    SET ConnectedAtUtc = COALESCE(ConnectedAtUtc, @Now),
        LastSeenUtc = @Now,
        Label = COALESCE(Label, N'Kijelző ' + CAST(id AS NVARCHAR(20)))
    WHERE id = @ResolvedDisplayID;
END
ELSE IF @UserID IS NOT NULL
BEGIN
    DECLARE @JwtTokenKey NVARCHAR(80) = N'jwt_user_' + CAST(@UserID AS NVARCHAR(30));
    SELECT TOP 1 @ResolvedDisplayID = id
    FROM [PTA].[tblEventDisplayToken]
    WHERE EventID = @EventID AND Module = 'op' AND Token = @JwtTokenKey
    ORDER BY id DESC;

    IF @ResolvedDisplayID IS NULL
    BEGIN
        INSERT INTO [PTA].[tblEventDisplayToken] (EventID, Module, Pin, Token, ExpiresAtUtc, ActiveFlg, TokenActiveFlg, ConnectedAtUtc, LastSeenUtc)
        VALUES (@EventID, 'op', 'JWT', @JwtTokenKey, DATEADD(hour, 24, SYSUTCDATETIME()), 1, 1, @Now, @Now);
        SET @ResolvedDisplayID = SCOPE_IDENTITY();
        UPDATE [PTA].[tblEventDisplayToken] SET Label = N'Kijelző ' + CAST(@ResolvedDisplayID AS NVARCHAR(20)) WHERE id = @ResolvedDisplayID;
    END
    ELSE
    BEGIN
        UPDATE [PTA].[tblEventDisplayToken]
        SET ActiveFlg = 1, TokenActiveFlg = 1, ConnectedAtUtc = COALESCE(ConnectedAtUtc, @Now), LastSeenUtc = @Now
        WHERE id = @ResolvedDisplayID;
    END
END

IF @ResolvedDisplayID IS NOT NULL AND OBJECT_ID('[OP].[tblClientConnection]', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM [OP].[tblClientConnection] WHERE EventID = @EventID AND ConnectionId = @ConnectionId AND RoleGroup = 'display')
    BEGIN
        UPDATE [OP].[tblClientConnection]
        SET UserID = @UserID, DisplayID = @ResolvedDisplayID, LastSeenUtc = @Now, ActiveFlg = 1
        WHERE EventID = @EventID AND ConnectionId = @ConnectionId AND RoleGroup = 'display';
    END
    ELSE
    BEGIN
        INSERT INTO [OP].[tblClientConnection] (EventID, ConnectionId, RoleGroup, UserID, DisplayID, ConnectedAtUtc, LastSeenUtc, ActiveFlg)
        VALUES (@EventID, @ConnectionId, 'display', @UserID, @ResolvedDisplayID, @Now, @Now, 1);
    END
END

SELECT @StateVersion = ISNULL(StateVersion, 0) FROM [OP].[tblEventSettings] WHERE EventID = @EventID;
SELECT @StateVersion AS StateVersion;

IF @ResolvedDisplayID IS NOT NULL AND OBJECT_ID('[OP].[tblClientConnection]', 'U') IS NOT NULL
BEGIN
    SELECT ConnectionId
    FROM [OP].[tblClientConnection]
    WHERE EventID = @EventID AND RoleGroup = 'display' AND DisplayID = @ResolvedDisplayID AND ActiveFlg = 1 AND ConnectionId != @ConnectionId;
END";

                            using (var dispCmd = new Microsoft.Data.SqlClient.SqlCommand(dispSql, connDisp))
                            {
                                dispCmd.Parameters.AddWithValue("@EventID", dispEventId);
                                dispCmd.Parameters.AddWithValue("@DisplayID", authorizedDisplayId.HasValue ? (object)authorizedDisplayId.Value : DBNull.Value);
                                dispCmd.Parameters.AddWithValue("@UserID", userId.HasValue ? (object)userId.Value : DBNull.Value);
                                dispCmd.Parameters.AddWithValue("@ConnectionId", payload.ConnectionId);

                                using (var r = await dispCmd.ExecuteReaderAsync())
                                {
                                    if (await r.ReadAsync() && !r.IsDBNull(0))
                                    {
                                        stateVersion = Convert.ToInt64(r.GetValue(0));
                                    }
                                    if (await r.NextResultAsync())
                                    {
                                        while (await r.ReadAsync())
                                        {
                                            if (!r.IsDBNull(0)) otherDispConns.Add(r.GetString(0));
                                        }
                                    }
                                }
                            }

                            if (otherDispConns.Count > 0)
                            {
                                var checks = await Task.WhenAll(otherDispConns.Select(async cid => (cid, alive: await SignalRManagementHelper.IsConnectionAliveAsync(cid))));
                                var deadIds = checks.Where(x => !x.alive).Select(x => x.cid).ToList();
                                foreach (var deadId in deadIds)
                                {
                                    using var delCmd = new Microsoft.Data.SqlClient.SqlCommand("UPDATE [OP].[tblClientConnection] SET ActiveFlg = 0 WHERE EventID = @EventID AND ConnectionId = @ConnectionId", connDisp);
                                    delCmd.Parameters.AddWithValue("@EventID", dispEventId);
                                    delCmd.Parameters.AddWithValue("@ConnectionId", deadId);
                                    await delCmd.ExecuteNonQueryAsync();
                                }
                            }
                        }

                        await SignalRManagementHelper.TryPublishConnectionsChangedAsync(_serviceBusClient, dispEventId, stateVersion);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, $"Failed to track Olimpub display connection for EventID={dispEventId}.");
                    }
                }
            }

            var actions = new List<SignalRGroupAction>();
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
