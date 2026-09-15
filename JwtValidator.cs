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
        public static ClaimsPrincipal? ValidateTokenAndGetPrincipal(HttpRequestData req, string jwtSecret)
        {
            try
            {
                if (!req.Headers.TryGetValues("Authorization", out var authHeaders))
                    return null; 

                var bearerToken = authHeaders.FirstOrDefault();
                if (string.IsNullOrEmpty(bearerToken) || !bearerToken.StartsWith("Bearer "))
                    return null; 

                var token = bearerToken.Substring("Bearer ".Length).Trim();
                var tokenHandler = new JwtSecurityTokenHandler();
                var key = Encoding.ASCII.GetBytes(jwtSecret);

                var validationParameters = new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(key),
                    ValidateIssuer = false,   
                    ValidateAudience = false, 
                    ValidateLifetime = true,  
                    ClockSkew = TimeSpan.Zero 
                };

                var principal = tokenHandler.ValidateToken(token, validationParameters, out SecurityToken validatedToken);
                return principal;
            }
            catch
            {
                return null;
            }
        }

        public static int? ValidateTokenAndGetUserId(HttpRequestData req, string jwtSecret)
        {
            var principal = ValidateTokenAndGetPrincipal(req, jwtSecret);
            if (principal == null) return null;
            
            var userIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
            if (userIdClaim != null && int.TryParse(userIdClaim.Value, out int userId))
            {
                return userId;
            }
            return null;
        }

        public static bool IsSysadmin(ClaimsPrincipal principal)
        {
            return principal.HasClaim(c => c.Type == "sysadmin" && c.Value == "true");
        }
    }
}
