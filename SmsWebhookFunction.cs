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
    public class SmsWebhookFunction
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;

        public SmsWebhookFunction(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SmsWebhookFunction>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") 
                ?? throw new InvalidOperationException("SqlConnectionString is missing.");
        }

        [Function("SmsWebhookFunction")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", "head", Route = "webhooks/bulkgate")] HttpRequestData req)
        {
            _logger.LogInformation("Received BulkGate Delivery Report (DLR) Webhook.");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            
            if (req.Method.Equals("get", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(requestBody))
            {
                _logger.LogInformation("Received GET request or empty body from BulkGate ping.");
                return req.CreateResponse(System.Net.HttpStatusCode.OK);
            }

            try
            {
                var payload = JsonConvert.DeserializeObject<BulkGateDlrPayload>(requestBody);

                if (payload == null)
                {
                    _logger.LogWarning("Empty payload received from BulkGate Webhook.");
                    return req.CreateResponse(System.Net.HttpStatusCode.OK); // Return 200 to satisfy ping/test
                }

                if (string.IsNullOrEmpty(payload.ActualMessageId))
                {
                    _logger.LogInformation("Received non-actionable or test webhook from BulkGate (Missing MessageId).");
                    return req.CreateResponse(System.Net.HttpStatusCode.OK); // Return 200 to satisfy ping/test
                }

                DateTimeOffset? deliveredAt = null;
                DateTimeOffset? bufferedAt = null;

                if (payload.Status == 1) // Delivered
                {
                    deliveredAt = DateTimeOffset.UtcNow;
                }
                else if (payload.Status == 2) // Buffered
                {
                    bufferedAt = DateTimeOffset.UtcNow;
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spUpdateSMSOutboxProviderStatus]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ProviderID", payload.ActualMessageId);
                        cmd.Parameters.AddWithValue("@ProviderStatusID", payload.Status);
                        cmd.Parameters.AddWithValue("@DeliveredAt", deliveredAt ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@BufferedAt", bufferedAt ?? (object)DBNull.Value);

                        await cmd.ExecuteNonQueryAsync();
                    }
                }

                _logger.LogInformation($"Successfully processed DLR for MessageID {payload.ActualMessageId}. Status: {payload.Status}");
                return req.CreateResponse(System.Net.HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing BulkGate Webhook.");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }
    }

    public class BulkGateDlrPayload
    {
        [JsonProperty("message_id")]
        public string? MessageId { get; set; }

        [JsonProperty("sms_id")]
        public string? SmsId { get; set; }

        public string? ActualMessageId => MessageId ?? SmsId;

        [JsonProperty("status")]
        public int Status { get; set; }

        [JsonProperty("status_text")]
        public string? StatusText { get; set; }

        [JsonProperty("number")]
        public string? Number { get; set; }

        [JsonProperty("price")]
        public decimal? Price { get; set; }
    }
}
