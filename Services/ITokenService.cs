namespace VexTrainer.Data.Services;

/// <summary>
/// Defines the contract for token generation used during authentication.
///
/// Implemented by the concrete TokenService class and injected into AuthService via this
/// interface so the token strategy can be swapped or mocked in tests without changing the
/// auth layer. Two token types are produced:
///
///   Access token  — a short-lived JWT embedded in every API request to prove identity.
///   Refresh token — a long-lived opaque string stored server-side, used only to obtain
///                   a new access token when the current one expires.
/// </summary>
public interface ITokenService {
  /// <summary>
  /// Generates a signed JWT access token encoding the user's identity and role.
  ///
  /// The returned token is passed back to the client at login/registration and must be
  /// included in the Authorization header of subsequent API calls. The expiry date is
  /// also returned so the client knows exactly when to request a refresh without having
  /// to decode the JWT itself.
  ///
  /// The email parameter is optional; it is included in the token claims when available
  /// (e.g., at registration) but omitted in flows where it is not needed (e.g., token
  /// refresh), which is why it defaults to an empty string.
  /// </summary>
  /// <param name="userId">The user's numeric database ID — embedded as a claim.</param>
  /// <param name="userName">The user's display name — embedded as a claim.</param>
  /// <param name="roleName">The user's role (e.g., "User", "Admin") — used for authorization checks.</param>
  /// <param name="email">The user's email address — optional claim, defaults to empty string.</param>
  /// <returns>A tuple of (token, expiryDate) where token is the raw JWT string and
  /// expiryDate is the UTC time at which it expires.</returns>
  (string token, DateTime expiryDate) GenerateAccessToken(int userId, string userName, string roleName, string email = "");

  /// <summary>
  /// Generates a cryptographically random refresh token.
  ///
  /// The returned string is opaque — it carries no user information and is meaningless
  /// outside the database. It is stored server-side in the session table and exchanged
  /// for a new access token via the refresh endpoint. Using a separate opaque token (rather
  /// than extending the JWT lifetime) allows the server to revoke sessions individually
  /// without changing the signing key.
  /// </summary>
  /// <returns>A random, URL-safe string suitable for use as a refresh token.</returns>
  string GenerateRefreshToken();
}