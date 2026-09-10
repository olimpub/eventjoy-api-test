using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class SignalREndpoints
    {
        private readonly ILogger _logger;

        private readonly string _sqlConnectionString;
        private readonly string _jwtSecret;

        public SignalREndpoints(ILoggerFactory loggerFactory, Microsoft.Extensions.Configuration.IConfiguration configuration)
        {
            _logger = loggerFactory.CreateLogger<SignalREndpoints>();
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
            _jwtSecret = configuration["JwtSecret"] ?? string.Empty;
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

            // 1. Try Display Token
            string? displayToken = null;
            if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues))
            {
                displayToken = System.Linq.Enumerable.FirstOrDefault(headerValues);
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
                    if (scalar != null)
                    {
                        authorizedDisplayEventId = (int)scalar;
                    }
                }
            }

            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            var authorizedStaffEventIds = new System.Collections.Generic.HashSet<int>();

            foreach (var group in payload.GroupNames)
            {
                if (string.IsNullOrEmpty(group)) continue;
                
                // If it's a TV with display-token, it MUST NOT join gamer/organizer/user groups
                if (!string.IsNullOrEmpty(displayToken) && userId == null)
                {
                    if (group.EndsWith("_gamer") || group.EndsWith("_organizer") || group.EndsWith("_contributor") || group.EndsWith("_participant") || group.Contains("_user_"))
                    {
                        _logger.LogWarning("TV tried to join restricted group.");
                        return new SignalRJoinOutput { HttpResponse = req.CreateResponse(HttpStatusCode.Forbidden) };
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
                                    var authCmd = new Microsoft.Data.SqlClient.SqlCommand("SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND r.RoleTypeID IN (1, 2)", connAuth);
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
                }
            }

            return new SignalRJoinOutput { Actions = actions.ToArray(), HttpResponse = req.CreateResponse(HttpStatusCode.OK) };
        }
    }
}





