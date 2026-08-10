using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class MasterDataEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;

        public MasterDataEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<MasterDataEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
        }

        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                list.Add(row);
            }
            return list;
        }

        [Function("GetMasterData")]
        public async Task<HttpResponseData> GetMasterData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "master/data")] HttpRequestData req)
        {
            // A MasterData lehet anonim vagy védett is. Általában publikus, vagy elég egy alap JWT validáció.
            // Ebben az architektúrában a Store hívja meg bejelentkezés után, szóval lehetne JWT védett is, 
            // de törzsadatok esetén opcionális lehet. Hagyjuk anonimnak, de lekérjük az adatokat.
            
            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetMasterData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;

                        int returnValue = 0;
                        string returnDescription = string.Empty;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteStringAsync(returnDescription);
                                return errRes;
                            }

                            List<Dictionary<string, object?>> eventTypes = new(), eventTypeGroups = new(), notificationTypes = new(), 
                                roleTypes = new(), roles = new(), loginIdentifierTypes = new(), userStatuses = new(), 
                                chatThreadTypes = new(), eventStatuses = new(), eventUserStatuses = new();
                            object? dataVersion = null;

                            if (await reader.NextResultAsync()) eventTypes = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) eventTypeGroups = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) notificationTypes = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) roleTypes = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) roles = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) loginIdentifierTypes = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) userStatuses = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) chatThreadTypes = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) eventStatuses = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) eventUserStatuses = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) dataVersion = (await ReadResultSetAsync(reader)).FirstOrDefault();

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new
                            {
                                EventTypes = eventTypes,
                                EventTypeGroups = eventTypeGroups,
                                NotificationTypes = notificationTypes,
                                RoleTypes = roleTypes,
                                Roles = roles,
                                LoginIdentifierTypes = loginIdentifierTypes,
                                UserStatuses = userStatuses,
                                ChatThreadTypes = chatThreadTypes,
                                EventStatuses = eventStatuses,
                                EventUserStatuses = eventUserStatuses,
                                DataVersion = dataVersion
                            });
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching master data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
