using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace EventJoy.Api
{
    public class SmsRouterFunction
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _appId;
        private readonly string _appToken;
        private static readonly HttpClient _httpClient = new HttpClient();

        public SmsRouterFunction(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SmsRouterFunction>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") 
                ?? throw new InvalidOperationException("SqlConnectionString is missing.");
            _appId = Environment.GetEnvironmentVariable("BulkGateAppId") 
                ?? throw new InvalidOperationException("BulkGateAppId is missing.");
            _appToken = Environment.GetEnvironmentVariable("BulkGateAppToken") 
                ?? throw new InvalidOperationException("BulkGateAppToken is missing.");
        }

        [Function("SmsRouterFunction")]
        public async Task Run([ServiceBusTrigger("communication", "sms", Connection = "ServiceBusConnection")] string mySbMsg)
        {
            _logger.LogInformation($"C# ServiceBus trigger processing SMS message: {mySbMsg}");

            int smsId = 0;
            try
            {
                var sbPayload = JsonConvert.DeserializeObject<dynamic>(mySbMsg);
                smsId = (int)sbPayload.SmsId;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to parse SMS Service Bus message.");
                return;
            }

            Dictionary<string, object?>? smsData = null;

            using (var conn = new SqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spGetSMSData]", conn))
                {
                    cmd.CommandType = System.Data.CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ID", smsId);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            var rs1 = ReadCurrentRow(reader);
                            if (TryGetInt(rs1, "ReturnValue") != 1) return;
                        }

                        await reader.NextResultAsync(); // Skip RS2
                        
                        if (await reader.NextResultAsync() && await reader.ReadAsync())
                        {
                            smsData = ReadCurrentRow(reader);
                        }
                    }
                }
            }

            if (smsData == null) return;

            string recipientPhone = smsData["RecipientPhone"]?.ToString() ?? "";
            string messageContent = smsData["MessageContent"]?.ToString() ?? "";
            string senderType = smsData["SenderType"]?.ToString() ?? "gText";
            string senderName = smsData["SenderName"]?.ToString() ?? "EventJoyApp";

            // Prepare BulkGate payload (Simple API requires credentials in the body)
            var bulkGatePayload = new
            {
                application_id = _appId,
                application_token = _appToken,
                number = recipientPhone,
                text = messageContent,
                sender_id = senderType,
                sender_id_value = senderName
            };

            var content = new StringContent(JsonConvert.SerializeObject(bulkGatePayload), Encoding.UTF8, "application/json");

            // BulkGate Simple Transactional API endpoint
            var response = await _httpClient.PostAsync("https://portal.bulkgate.com/api/1.0/simple/transactional", content);
            string responseString = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                throw new Exception($"BulkGate API error: {response.StatusCode} - {responseString}");
            }

            // Parse response
            var jsonResponse = JObject.Parse(responseString);
            var providerId = jsonResponse["data"]?["sms_id"]?.ToString() 
                          ?? jsonResponse["data"]?["message_id"]?.ToString();
            
            if (string.IsNullOrEmpty(providerId) && jsonResponse["data"] is JArray arr && arr.Count > 0)
            {
                providerId = arr[0]["sms_id"]?.ToString() ?? arr[0]["message_id"]?.ToString();
            }

            // Update DB Status
            using (var conn = new SqlConnection(_connectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spUpdateSMSOutboxStatus]", conn))
                {
                    cmd.CommandType = System.Data.CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ID", smsId);
                    cmd.Parameters.AddWithValue("@ProviderID", providerId ?? "unknown");
                    cmd.Parameters.AddWithValue("@StatusID", 2); // 2 = Sent to BulkGate

                    await cmd.ExecuteNonQueryAsync();
                }
            }
            
            _logger.LogInformation($"Successfully sent SMS ID {smsId} to BulkGate. ProviderID: {providerId}");
            
            // Tiny delay to respect BulkGate simple limits during bursts
            await Task.Delay(100);
        }

        private static Dictionary<string, object?> ReadCurrentRow(SqlDataReader reader)
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < reader.FieldCount; i++)
            {
                row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }
            return row;
        }

        private static int? TryGetInt(IDictionary<string, object?> source, string key)
        {
            if (!source.TryGetValue(key, out var value) || value == null) return null;
            return Convert.ToInt32(value);
        }
    }
}
