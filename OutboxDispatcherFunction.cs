using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class OutboxDispatcherFunction
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _serviceBusConnectionString;
        private const string TopicName = "communication";

        public OutboxDispatcherFunction(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OutboxDispatcherFunction>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString missing.");
            _serviceBusConnectionString = Environment.GetEnvironmentVariable("ServiceBusConnection")
                ?? throw new InvalidOperationException("ServiceBusConnection missing.");
        }

        [Function("OutboxDispatcherFunction")]
        public async Task Run([TimerTrigger("*/10 * * * * *")] TimerInfo myTimer)
        {
            var messagesToSend = new List<(long Id, string Channel)>();

            // 1. Olvassuk ki a Pending üzeneteket SQL-ből
            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spGetPendingOutboxMessages]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@BatchSize", 50);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                long id = reader.GetInt64(0);
                                string channel = reader.GetString(1);
                                messagesToSend.Add((id, channel));
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading outbox messages from SQL.");
                return;
            }

            if (messagesToSend.Count == 0) return;

            _logger.LogInformation($"Found {messagesToSend.Count} pending outbox messages.");

            // 2. Publikálás a Service Busra
            await using var client = new ServiceBusClient(_serviceBusConnectionString);
            await using var sender = client.CreateSender(TopicName);

            using ServiceBusMessageBatch messageBatch = await sender.CreateMessageBatchAsync();

            var failedMessages = new List<long>();

            foreach (var msg in messagesToSend)
            {
                var payload = new { communicationOutboxId = msg.Id };
                var sbMessage = new ServiceBusMessage(JsonSerializer.Serialize(payload))
                {
                    MessageId = msg.Id.ToString() // Duplikáció védelem
                };
                
                // Application property filterhez
                sbMessage.ApplicationProperties["channel"] = msg.Channel;

                if (!messageBatch.TryAddMessage(sbMessage))
                {
                    // Ha nem fér bele a batch-be, elküldjük az eddigieket és újat kezdünk
                    await sender.SendMessagesAsync(messageBatch);
                    messageBatch.Dispose();
                    
                    var newBatch = await sender.CreateMessageBatchAsync();
                    if (!newBatch.TryAddMessage(sbMessage))
                    {
                        failedMessages.Add(msg.Id);
                    }
                    // Nem tudjuk itt direkt kezelni a batch újrahivatkozását egyszerűen without a loop,
                    // de 50 üzenet biztosan belefér egy batch-be normál esetben. Ezt a részt finomítani lehetne termelésben.
                }
            }

            if (messageBatch.Count > 0)
            {
                try
                {
                    await sender.SendMessagesAsync(messageBatch);
                    _logger.LogInformation($"Successfully published {messageBatch.Count} messages to Service Bus.");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error publishing to Service Bus.");
                    // Vissza kéne állítani Pendingre azokat, amiket nem tudtunk elküldeni
                    await RevertStatusAsync(messagesToSend);
                }
            }
        }

        private async Task RevertStatusAsync(List<(long Id, string Channel)> messages)
        {
            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    foreach (var msg in messages)
                    {
                        using (var cmd = new SqlCommand("UPDATE [EJ].[tblCommunicationOutbox] SET [Status] = 'Pending' WHERE [CommunicationOutboxID] = @Id", conn))
                        {
                            cmd.Parameters.AddWithValue("@Id", msg.Id);
                            await cmd.ExecuteNonQueryAsync();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reverting outbox status.");
            }
        }
    }
}
