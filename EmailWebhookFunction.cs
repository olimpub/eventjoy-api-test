using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class EmailWebhookFunction
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;

        public EmailWebhookFunction(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<EmailWebhookFunction>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") 
                ?? throw new InvalidOperationException("SqlConnectionString is missing.");
        }

        [Function("EmailWebhookFunction")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "webhooks/mailersend")] HttpRequestData req)
        {
            _logger.LogInformation("Received MailerSend Webhook.");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            
            try
            {
                var payload = JsonConvert.DeserializeObject<MailerSendWebhookPayload>(requestBody);

                if (payload == null)
                {
                    _logger.LogWarning("Empty payload received from MailerSend Webhook.");
                    return req.CreateResponse(System.Net.HttpStatusCode.OK); // Return 200 to satisfy MailerSend ping/test
                }

                if (payload.Data == null || string.IsNullOrEmpty(payload.Data.MessageId) || string.IsNullOrEmpty(payload.Data.Recipient))
                {
                    _logger.LogInformation($"Received non-actionable or test webhook from MailerSend. Type: {payload.Type}");
                    return req.CreateResponse(System.Net.HttpStatusCode.OK); // Return 200 to satisfy MailerSend ping/test
                }

                // If it's a bulk email, the message_id is often prefixed with "bulk:". Strip it out so it matches our DB MailerSendID
                string actualMessageId = payload.Data.MessageId;
                if (actualMessageId.StartsWith("bulk:"))
                {
                    actualMessageId = actualMessageId.Substring(5);
                }

                short providerStatusId = 0;
                
                switch (payload.Type)
                {
                    case "activity.delivered":
                        providerStatusId = 1;
                        break;
                    case "activity.soft_bounced":
                    case "activity.hard_bounced":
                    case "activity.rejected":
                        providerStatusId = 2;
                        break;
                    case "activity.opened":
                        providerStatusId = 3;
                        break;
                    case "activity.clicked":
                        providerStatusId = 4;
                        break;
                    default:
                        // Ignore other events (like sent, processed)
                        return req.CreateResponse(System.Net.HttpStatusCode.OK);
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spUpdateEmailOutboxProviderStatus]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@MailerSendID", actualMessageId);
                        cmd.Parameters.AddWithValue("@EmailAddress", payload.Data.Recipient);
                        cmd.Parameters.AddWithValue("@ProviderStatusID", providerStatusId);
                        cmd.Parameters.AddWithValue("@ActionDate", DateTimeOffset.UtcNow);

                        await cmd.ExecuteNonQueryAsync();
                    }
                }

                _logger.LogInformation($"Successfully processed MailerSend DLR for MessageID {actualMessageId}, Email {payload.Data.Recipient}. Status: {providerStatusId}");
                return req.CreateResponse(System.Net.HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing MailerSend Webhook.");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }
    }

    public class MailerSendWebhookPayload
    {
        [JsonProperty("type")]
        public string? Type { get; set; }

        [JsonProperty("data")]
        public MailerSendData? Data { get; set; }
    }

    public class MailerSendData
    {
        [JsonProperty("message_id")]
        public string? MessageId { get; set; }

        [JsonProperty("recipient")]
        public string? Recipient { get; set; }
    }
}
