using System;
using System.Data.SqlClient;

string connStr = "Server=tcp:pulsator-prod.database.windows.net,1433;Initial Catalog=eventjoy-test;Persist Security Info=False;User ID=eventjoyapi;Password=e5i4VqHPLpjsoreRe;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;";

try {
    using (var conn = new SqlConnection(connStr)) {
        conn.Open();
        using (var cmd = new SqlCommand("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'EJ'", conn)) {
            using (var reader = cmd.ExecuteReader()) {
                while (reader.Read()) {
                    Console.WriteLine(reader[0]);
                }
            }
        }
    }
} catch (Exception ex) {
    Console.WriteLine("ERROR: " + ex.Message);
}
