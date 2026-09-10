using System;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker.Http;

namespace EventJoy.Api
{
    public class SignalRMessagePayload
    {
        public string TargetGroup { get; set; } = string.Empty;
        public string EventName { get; set; } = string.Empty;
        public object? PayloadJson { get; set; }
    }

    public class SignalRRouterFunction
    {
        private readonly ILogger _logger;

        public SignalRRouterFunction(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SignalRRouterFunction>();
        }

        [Function("SignalRRouterFunction")]
        [SignalROutput(HubName = "eventHub", ConnectionStringSetting = "AzureSignalRConnectionString")]
        public SignalRMessageAction? Run(
            [ServiceBusTrigger("communication", "signalr", Connection = "ServiceBusConnection")] string mySbMsg)
        {
            _logger.LogInformation($"SignalRRouter received message: {mySbMsg}");

            try
            {
                var payload = JsonSerializer.Deserialize<SignalRMessagePayload>(mySbMsg, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                
                if (payload == null || string.IsNullOrEmpty(payload.TargetGroup) || string.IsNullOrEmpty(payload.EventName))
                {
                    _logger.LogWarning("Invalid SignalR payload. Missing TargetGroup or EventName.");
                    return null;
                }

                _logger.LogInformation($"Broadcasting to group {payload.TargetGroup}: {payload.EventName}");

                return new SignalRMessageAction(payload.EventName)
                {
                    GroupName = payload.TargetGroup,
                    Arguments = new object[] { payload.PayloadJson! }
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error processing SignalR message: {ex.Message}");
                throw;
            }
        }
    }
}


