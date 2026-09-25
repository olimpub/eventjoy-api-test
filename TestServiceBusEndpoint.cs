using System;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class TestServiceBusEndpoint
    {
        private readonly ILogger _logger;
        private readonly string _serviceBusConnectionString;

        public TestServiceBusEndpoint(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<TestServiceBusEndpoint>();
            _serviceBusConnectionString = Environment.GetEnvironmentVariable("ServiceBusConnection") 
                ?? throw new InvalidOperationException("ServiceBusConnection missing");
        }

        [Function("PostTestServiceBus")]
        public async Task<HttpResponseData> Run([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "test/send-email-trigger/{mailId}")] HttpRequestData req, string mailId)
        {
            if (!Guid.TryParse(mailId, out Guid parsedMailId))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen GUID!" });
                return badReq;
            }

            // Kapcsolódás a Service Bus-hoz
            await using var client = new ServiceBusClient(_serviceBusConnectionString);
            await using var sender = client.CreateSender("communication");
            
            // Üzenet összerakása
            var payload = new { MailId = parsedMailId };
            var sbMessage = new ServiceBusMessage(JsonSerializer.Serialize(payload))
            {
                MessageId = parsedMailId.ToString() // Duplikáció védelem
            };
            
            // Szűrő property beállítása
            sbMessage.ApplicationProperties["channel"] = "email";
            
            // Publikálás a Topicra
            await sender.SendMessageAsync(sbMessage);
            
            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = $"Sikeresen felküldve a Service Busra! UID: {parsedMailId}\nNézd a terminál logot, hogy elindult-e az EmailRouterFunction!" });
            return response;
        }
    }
}
