using System;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Security.Claims;
using System.Text;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.IdentityModel.Tokens;

namespace EventJoy.Api
{
    public static class JwtValidator
    {
        /// <summary>
        /// Ellenőrzi a HTTP kérés fejlécében lévő JWT Tokent, és visszaadja a UserID-t.
        /// Hamisított, hiányzó vagy lejárt token esetén null-t ad vissza.
        /// </summary>
        public static int? ValidateTokenAndGetUserId(HttpRequestData req, string jwtSecret)
        {
            try
            {
                // 1. Megkeressük az "Authorization" fejlécet
                if (!req.Headers.TryGetValues("Authorization", out var authHeaders))
                {
                    return null; 
                }

                var bearerToken = authHeaders.FirstOrDefault();
                if (string.IsNullOrEmpty(bearerToken) || !bearerToken.StartsWith("Bearer "))
                {
                    return null; 
                }

                // 2. Levágjuk a "Bearer " szót az elejéről
                var token = bearerToken.Substring("Bearer ".Length).Trim();

                // 3. Validálási szabályok felállítása (az általad megadott titkos kulccsal)
                var tokenHandler = new JwtSecurityTokenHandler();
                var key = Encoding.ASCII.GetBytes(jwtSecret);

                var validationParameters = new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(key),
                    ValidateIssuer = false,   // Belső rendszer, nem szigorítjuk az Issuert
                    ValidateAudience = false, // Belső rendszer, nem szigorítjuk az Audience-t
                    ValidateLifetime = true,  // Szigorúan ellenőrizzük a lejárati időt!
                    ClockSkew = TimeSpan.Zero // Ne hagyjon extra perceket a lejárat után
                };

                // 4. Token matematikai validálása
                // Ha rossz a token, ez a sor hibát (Exception) fog dobni, ami egyenesen a catch blokkba ugrik
                var principal = tokenHandler.ValidateToken(token, validationParameters, out SecurityToken validatedToken);

                // 5. UserID kibányászása a Payload-ból
                var userIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
                if (userIdClaim != null && int.TryParse(userIdClaim.Value, out int userId))
                {
                    return userId; // Kész! Megvan a biztonságosan azonosított UserID!
                }

                return null;
            }
            catch
            {
                // Token lejárt, vagy valaki belenyúlt (hamisított) -> Kirúgjuk
                return null;
            }
        }
    }
}
