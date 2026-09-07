using System;
using System.IO;
using System.Data.SqlClient;

string connStr = "Server=tcp:pulsator-prod.database.windows.net,1433;Initial Catalog=eventjoy-test;Persist Security Info=False;User ID=eventjoyapi;Password=e5i4VqHPLpjsoreRe;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;";

string json = @"{""EventID"": null, ""Event"": {""Title"": ""Teszt 2"", ""Description"": ""Teszt 2"", ""EventTypeID"": 46, ""EventStatusID"": 1, ""EventUID"": ""7f3c2a1b-9e44-4c10-8d2a-11b0c4e6f901"", ""StartAtUtc"": ""2026-09-12T08:00:00.000Z"", ""EndAtUtc"": ""2026-09-12T16:00:00.000Z"", ""OnlineFlg"": false, ""OnlineURL"": null, ""EventLocationID"": null, ""Capacity"": 40, ""PublicFlg"": false, ""ActiveFlg"": true, ""ContactName"": ""Kovács Anna"", ""ContactEmail"": ""anna@eventjoy.hu"", ""ContactPhone"": ""+36301234567"", ""OrganizationID"": null}, ""Location"": {""LocationName"": ""Platz Bisztró"", ""City"": ""Vecsés"", ""AddressLine1"": ""Telepi út 43"", ""CountryCode"": ""HU""}, ""Labels"": [{""id"": null, ""Name"": ""boardgame""}], ""Roles"": [{""TempId"": ""r-org"", ""RoleID"": 1, ""ActiveFlg"": true}], ""Tickets"": [{""TempId"": ""t-free"", ""Code"": ""EV-7F3C2A1B-T1-A91C"", ""TicketName"": ""Játékos"", ""Description"": """", ""Price"": 0, ""CurrencyCode"": ""HUF"", ""Capacity"": 32, ""RegistrationStartAtUtc"": ""2026-08-01T00:00:00.000Z"", ""RegistrationEndAtUtc"": ""2026-09-12T07:00:00.000Z"", ""TemplateID"": 2, ""ActiveFlg"": true}], ""RoleTickets"": [{""RoleTempId"": ""r-org"", ""TicketTempId"": ""t-free""}], ""PtaSettings"": {""GameTypeID"": 1, ""PairModeID"": 1, ""ChampionshipID"": null, ""ChampionshipFlg"": false, ""Category"": 1, ""Point1"": 10, ""Point2"": 7, ""Point3"": 5, ""Point4"": 3, ""MaxParticipants"": 32, ""OrganizationGrpFlg"": false, ""TeamGrpFlg"": true, ""RegionGrpFlg"": false, ""CompanyGrpFlg"": false, ""PhotoUploadMandatoryFlg"": false, ""ExtraPrizeFlg"": true, ""ShowUserPositionFlg"": true}, ""PtaPrizes"": []}";

try {
    using (var conn = new SqlConnection(connStr)) {
        conn.Open();
        using (var cmd = new SqlCommand("[EJ].[spSaveEvent]", conn)) {
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.AddWithValue("@Json", json);
            cmd.Parameters.AddWithValue("@UserID", 3);
            using (var reader = cmd.ExecuteReader()) {
                if (reader.Read()) {
                    Console.WriteLine("ReturnValue: " + reader["ReturnValue"]);
                    Console.WriteLine("ReturnDescription: " + reader["ReturnDescription"]);
                    Console.WriteLine("EventID: " + reader["EventID"]);
                } else {
                    Console.WriteLine("No rows returned.");
                }
            }
        }
    }
} catch (Exception ex) {
    Console.WriteLine("ERROR: " + ex.Message);
}
