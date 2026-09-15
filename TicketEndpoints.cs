using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using System.IO;
using Newtonsoft.Json;
using System.Data;
using System.Collections.Generic;

namespace EventJoy.Api
{
    public class TicketEndpoints
    {
        private readonly string _sqlConnectionString;
        private readonly string _jwtSecret;

        public TicketEndpoints(IConfiguration configuration)
        {
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
            _jwtSecret = configuration["JwtSecret"] ?? string.Empty;
        }

        [Function("GetTicketMetadata")]
        public async Task<HttpResponseData> GetTicketMetadata([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "tickets/metadata")] HttpRequestData req)
        {
            var response = req.CreateResponse(HttpStatusCode.OK);
            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spGetTicketMetadata]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        var result = new Dictionary<string, object>();
                        
                        if (await reader.ReadAsync()) // RS1: ReturnStatus
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1) return req.CreateResponse(HttpStatusCode.BadRequest);
                        }

                        // TicketTypes
                        if (await reader.NextResultAsync() && await reader.ReadAsync()) // ResultName
                        { }
                        if (await reader.NextResultAsync())
                        {
                            var types = new List<object>();
                            while (await reader.ReadAsync())
                            {
                                types.Add(new {
                                    id = reader.GetInt32(reader.GetOrdinal("TicketTypeID")),
                                    name = reader.GetString(reader.GetOrdinal("TypeName"))
                                });
                            }
                            result["types"] = types;
                        }

                        // TicketStatuses
                        if (await reader.NextResultAsync() && await reader.ReadAsync()) // ResultName
                        { }
                        if (await reader.NextResultAsync())
                        {
                            var statuses = new List<object>();
                            while (await reader.ReadAsync())
                            {
                                statuses.Add(new {
                                    id = reader.GetInt32(reader.GetOrdinal("TicketStatusID")),
                                    name = reader.GetString(reader.GetOrdinal("StatusName")),
                                    isClosedState = reader.GetBoolean(reader.GetOrdinal("IsClosedState"))
                                });
                            }
                            result["statuses"] = statuses;
                        }

                        await response.WriteAsJsonAsync(result);
                        return response;
                    }
                }
            }
        }

        [Function("CreateTicket")]
        public async Task<HttpResponseData> CreateTicket([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "tickets")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic? data = JsonConvert.DeserializeObject(requestBody);
            
            if (data == null || data!.title == null || data!.description == null || data!.ticketTypeId == null) 
                return req.CreateResponse(HttpStatusCode.BadRequest);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spCreateTicket]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ReporterUserID", userId.Value);
                    cmd.Parameters.AddWithValue("@Title", (string)data!.title);
                    cmd.Parameters.AddWithValue("@Description", (string)data!.description);
                    cmd.Parameters.AddWithValue("@TicketTypeID", (int)data!.ticketTypeId);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal == 1)
                            {
                                var response = req.CreateResponse(HttpStatusCode.OK);
                                await response.WriteAsJsonAsync(new { ticketId = reader.GetInt64(reader.GetOrdinal("TicketID")) });
                                return response;
                            }
                        }
                    }
                }
            }
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        [Function("GetUserTickets")]
        public async Task<HttpResponseData> GetUserTickets([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "tickets")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            var response = req.CreateResponse(HttpStatusCode.OK);
            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spGetUserTickets]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1) return req.CreateResponse(HttpStatusCode.BadRequest);
                        }

                        if (await reader.NextResultAsync() && await reader.ReadAsync()) { } // ResultName
                        
                        if (await reader.NextResultAsync())
                        {
                            var tickets = new List<object>();
                            while (await reader.ReadAsync())
                            {
                                tickets.Add(new {
                                    id = reader.GetInt64(reader.GetOrdinal("TicketID")),
                                    title = reader.GetString(reader.GetOrdinal("Title")),
                                    typeId = reader.GetInt32(reader.GetOrdinal("TicketTypeID")),
                                    typeName = reader.GetString(reader.GetOrdinal("TypeName")),
                                    statusId = reader.GetInt32(reader.GetOrdinal("StatusID")),
                                    statusName = reader.GetString(reader.GetOrdinal("StatusName")),
                                    isClosed = reader.GetBoolean(reader.GetOrdinal("IsClosedState")),
                                    updatedAt = reader.GetDateTimeOffset(reader.GetOrdinal("updatedAt")),
                                    createdAt = reader.GetDateTimeOffset(reader.GetOrdinal("createdAt"))
                                });
                            }
                            await response.WriteAsJsonAsync(tickets);
                            return response;
                        }
                    }
                }
            }
            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }

        [Function("GetTicketDetails")]
        public async Task<HttpResponseData> GetTicketDetails([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "tickets/{ticketId:long}")] HttpRequestData req, long ticketId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            var response = req.CreateResponse(HttpStatusCode.OK);
            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spGetTicketDetails]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@TicketID", ticketId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1) return req.CreateResponse(HttpStatusCode.Forbidden);
                        }

                        var result = new Dictionary<string, object>();

                        // Details
                        if (await reader.NextResultAsync() && await reader.ReadAsync()) { }
                        if (await reader.NextResultAsync() && await reader.ReadAsync())
                        {
                            result["details"] = new {
                                id = reader.GetInt64(reader.GetOrdinal("TicketID")),
                                title = reader.GetString(reader.GetOrdinal("Title")),
                                description = reader.GetString(reader.GetOrdinal("Description")),
                                typeName = reader.GetString(reader.GetOrdinal("TypeName")),
                                statusName = reader.GetString(reader.GetOrdinal("StatusName")),
                                isClosed = reader.GetBoolean(reader.GetOrdinal("IsClosedState")),
                                targetVersion = reader.IsDBNull(reader.GetOrdinal("TargetVersion")) ? null : reader.GetString(reader.GetOrdinal("TargetVersion")),
                                createdAt = reader.GetDateTimeOffset(reader.GetOrdinal("createdAt")),
                                updatedAt = reader.GetDateTimeOffset(reader.GetOrdinal("updatedAt"))
                            };
                        }

                        // Comments
                        if (await reader.NextResultAsync() && await reader.ReadAsync()) { }
                        if (await reader.NextResultAsync())
                        {
                            var comments = new List<object>();
                            while (await reader.ReadAsync())
                            {
                                comments.Add(new {
                                    id = reader.GetInt64(reader.GetOrdinal("CommentID")),
                                    senderType = reader.GetString(reader.GetOrdinal("SenderType")),
                                    text = reader.GetString(reader.GetOrdinal("CommentText")),
                                    isSystemMessage = reader.GetBoolean(reader.GetOrdinal("IsSystemMessage")),
                                    createdAt = reader.GetDateTimeOffset(reader.GetOrdinal("createdAt"))
                                });
                            }
                            result["comments"] = comments;
                        }

                        await response.WriteAsJsonAsync(result);
                        return response;
                    }
                }
            }
        }

        [Function("AddTicketComment")]
        public async Task<HttpResponseData> AddTicketComment([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "tickets/{ticketId:long}/comments")] HttpRequestData req, long ticketId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic? data = JsonConvert.DeserializeObject(requestBody);
            if (data == null || data!.text == null) return req.CreateResponse(HttpStatusCode.BadRequest);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spAddTicketComment]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@TicketID", ticketId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);
                    cmd.Parameters.AddWithValue("@CommentText", (string)data!.text);

                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null && (int)result == 1) return req.CreateResponse(HttpStatusCode.OK);
                }
            }
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }

        [Function("WithdrawTicket")]
        public async Task<HttpResponseData> WithdrawTicket([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "tickets/{ticketId:long}/withdraw")] HttpRequestData req, long ticketId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                using (var cmd = new SqlCommand("[EJ].[spWithdrawTicket]", conn))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@TicketID", ticketId);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);

                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null && (int)result == 1) return req.CreateResponse(HttpStatusCode.OK);
                }
            }
            return req.CreateResponse(HttpStatusCode.BadRequest);
        }
    }
}
