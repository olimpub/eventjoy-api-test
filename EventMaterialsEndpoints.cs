using System;
using System.Collections.Generic;
using System.Net;
using System.Security.Claims;
using System.Threading.Tasks;
using System.Linq;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;

namespace EventJoy.Api
{
    public class EventMaterialsEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;
        private readonly string _storageConnectionString;

        public EventMaterialsEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<EventMaterialsEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
            _storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage")
                ?? throw new InvalidOperationException("AzureWebJobsStorage app setting is missing.");
        }

        [Function("GetEventMaterialUploadUrl")]
        public async Task<HttpResponseData> GetEventMaterialUploadUrl(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/{eventId:long}/materials/upload-url")] HttpRequestData req,
            long eventId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string? fileName = query["fileName"];
            if (string.IsNullOrWhiteSpace(fileName)) return req.CreateResponse(HttpStatusCode.BadRequest);

            try
            {
                // Blob container setup
                var blobServiceClient = new BlobServiceClient(_storageConnectionString);
                var containerClient = blobServiceClient.GetBlobContainerClient("materials");
                await containerClient.CreateIfNotExistsAsync(Azure.Storage.Blobs.Models.PublicAccessType.None);

                string uniqueFileName = $"{Guid.NewGuid()}_{fileName}";
                var blobClient = containerClient.GetBlobClient(uniqueFileName);

                var sasBuilder = new BlobSasBuilder
                {
                    BlobContainerName = "materials",
                    BlobName = uniqueFileName,
                    Resource = "b",
                    StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                    ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(15) // As per spec: 15 min TTL
                };
                sasBuilder.SetPermissions(BlobSasPermissions.Write | BlobSasPermissions.Create);

                Uri sasUri = blobClient.GenerateSasUri(sasBuilder);

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { 
                    SasUrl = sasUri.ToString(),
                    BlobUrl = blobClient.Uri.ToString() 
                });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error generating SAS token");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        public class OrganizerCreateMaterialDto
        {
            public string? FileName { get; set; }
            public string? BlobUrl { get; set; }
            public string? ContentType { get; set; }
            public long SizeInBytes { get; set; }
            public string? PublicName { get; set; }
            public int MaterialTypeID { get; set; }
            public List<long>? EventRoleIDs { get; set; }
        }

        [Function("OrganizerCreateMaterial")]
        public async Task<HttpResponseData> OrganizerCreateMaterial(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "event/{eventId:long}/materials")] HttpRequestData req,
            long eventId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var data = System.Text.Json.JsonSerializer.Deserialize<OrganizerCreateMaterialDto>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            
            if (data == null || string.IsNullOrWhiteSpace(data.FileName) || string.IsNullOrWhiteSpace(data.BlobUrl) || data.MaterialTypeID <= 0) 
                return req.CreateResponse(HttpStatusCode.BadRequest);

            string? rolesJson = data.EventRoleIDs != null && data.EventRoleIDs.Any() 
                ? System.Text.Json.JsonSerializer.Serialize(data.EventRoleIDs) 
                : null;

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spOrganizerCreateEventMaterial]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", eventId);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@FileName", data.FileName);
                        cmd.Parameters.AddWithValue("@BlobUrl", data.BlobUrl);
                        cmd.Parameters.AddWithValue("@ContentType", data.ContentType ?? "application/octet-stream");
                        cmd.Parameters.AddWithValue("@SizeInBytes", data.SizeInBytes);
                        cmd.Parameters.AddWithValue("@PublicName", data.PublicName ?? data.FileName);
                        cmd.Parameters.AddWithValue("@MaterialTypeID", data.MaterialTypeID);
                        cmd.Parameters.AddWithValue("@EventRoleIDsJSON", rolesJson ?? (object)DBNull.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                                string returnDesc = reader.GetString(reader.GetOrdinal("ReturnDescription"));
                                
                                if (returnValue == -1 && returnDesc.StartsWith("Unauthorized"))
                                    return req.CreateResponse(HttpStatusCode.Forbidden);
                                
                                if (returnValue != 1)
                                {
                                    _logger.LogError($"SP Error: {returnDesc}");
                                    return req.CreateResponse(HttpStatusCode.InternalServerError);
                                }

                                int eventMaterialId = reader.GetInt32(reader.GetOrdinal("EventMaterialID"));
                                int materialId = reader.GetInt32(reader.GetOrdinal("MaterialID"));

                                var res = req.CreateResponse(HttpStatusCode.OK);
                                await res.WriteAsJsonAsync(new { EventMaterialID = eventMaterialId, MaterialID = materialId });
                                return res;
                            }
                        }
                    }
                }
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error linking material to event");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("OrganizerGetEventMaterials")]
        public async Task<HttpResponseData> OrganizerGetEventMaterials(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "event/{eventId:long}/materials")] HttpRequestData req,
            long eventId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            try
            {
                var materials = new List<Dictionary<string, object?>>();
                int returnValue = 1;
                string returnDesc = "OK";

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spOrganizerGetEventMaterials]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", eventId);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                                returnDesc = reader.GetString(reader.GetOrdinal("ReturnDescription"));
                                if (returnValue == -1 && returnDesc.StartsWith("Unauthorized"))
                                    return req.CreateResponse(HttpStatusCode.Forbidden);
                            }

                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var material = new Dictionary<string, object?>();
                                    for (int i = 0; i < reader.FieldCount; i++) material[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    material["Roles"] = new List<object?>();
                                    materials.Add(material);
                                }
                            }
                            
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var role = new Dictionary<string, object?>();
                                    for (int i = 0; i < reader.FieldCount; i++) role[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    
                                    var parentMat = materials.FirstOrDefault(m => (int)(m["EventMaterialID"] ?? 0) == (int)(role["EventMaterialID"] ?? 0));
                                    if (parentMat != null)
                                    {
                                        var rolesList = parentMat["Roles"] as List<object?>;
                                        rolesList?.Add(role);
                                    }
                                }
                            }
                        }
                    }
                }

                // Envelope according to event API standard
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { 
                    ReturnValue = returnValue,
                    ReturnDescription = returnDesc,
                    Data = materials 
                });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching event materials");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
