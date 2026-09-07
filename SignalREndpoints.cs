using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class SignalREndpoints
    {
        private readonly ILogger _logger;

        public SignalREndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SignalREndpoints>();
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
            public string ConnectionId { get; set; }
            public System.Collections.Generic.List<string> GroupNames { get; set; }
        }

        [Function("joinGroup")]
        [SignalROutput(HubName = "eventHub", ConnectionStringSetting = "AzureSignalRConnectionString")]
        public async Task<SignalRGroupAction[]> JoinGroup(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "signalr/join")] HttpRequestData req)
        {
            _logger.LogInformation("SignalR joinGroup requested.");
            var body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var payload = System.Text.Json.JsonSerializer.Deserialize<JoinGroupRequest>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            
            if (payload == null || string.IsNullOrEmpty(payload.ConnectionId) || payload.GroupNames == null || payload.GroupNames.Count == 0)
            {
                _logger.LogWarning("Invalid joinGroup payload.");
                return null;
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

            return actions.ToArray();
        }
    }
}
