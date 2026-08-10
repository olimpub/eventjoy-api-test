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
    public class EventEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public EventEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<EventEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? throw new InvalidOperationException("JwtSecret app setting is missing.");
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

        [Function("GetEventData")]
        public async Task<HttpResponseData> GetEventData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/data")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);

            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetEventData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

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

                            List<Dictionary<string, object?>> events = new(), invitations = new(), eventLabels = new(), 
                                labels = new(), locations = new(), roles = new(), roleTickets = new(), 
                                tickets = new(), eventUsers = new(), ownerTypes = new();

                            if (await reader.NextResultAsync()) events = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) invitations = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) eventLabels = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) labels = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) locations = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) roles = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) roleTickets = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) tickets = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) eventUsers = await ReadResultSetAsync(reader);
                            if (await reader.NextResultAsync()) ownerTypes = await ReadResultSetAsync(reader);

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(new
                            {
                                Events = events,
                                Invitations = invitations,
                                EventLabels = eventLabels,
                                Labels = labels,
                                Locations = locations,
                                Roles = roles,
                                RoleTickets = roleTickets,
                                Tickets = tickets,
                                EventUsers = eventUsers,
                                EventTypeOwners = ownerTypes
                            });
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching event data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
