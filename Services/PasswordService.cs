using System.Text.RegularExpressions;

namespace VexTrainer.Data.Services;

/// <summary>
/// Handles all password-related operations for VexTrainer: hashing new passwords,
/// verifying supplied passwords against stored hashes, and enforcing strength rules.
///
/// All hashing and verification uses BCrypt, which is the correct algorithm for password
/// storage because it is intentionally slow (controlled by the work factor), automatically
/// salts every hash, and embeds both the salt and cost parameter inside the resulting
/// 60-character string — meaning no separate salt column is needed in the database.
///
/// This service has no database dependency and no injected state; it can be instantiated
/// directly or registered as a singleton. It is consumed by AuthService, which calls
/// ValidatePassword before any write operation and VerifyPassword during login and
/// password-change flows.
/// </summary>
public class PasswordService {
  /// <summary>
  /// BCrypt cost factor — controls how much CPU work is required per hash operation.
  /// Higher values make brute-force attacks exponentially slower. 11 sits in the
  /// middle of the recommended production range (10–12): secure enough to resist
  /// offline cracking while still completing in well under a second for a single login.
  /// Raise this value as hardware improves; existing hashes remain verifiable because
  /// the cost is stored inside the hash string itself.
  /// </summary>
  private const int WorkFactor = 11;

  /// <summary>
  /// Produces a BCrypt hash of the supplied plain-text password, ready to store in
  /// the database.
  ///
  /// BCrypt generates a unique cryptographic salt internally for every call, so two
  /// hashes of the same password will never be identical — there is no need to manage
  /// or store a separate salt value. The returned 60-character string encodes the
  /// algorithm version, cost factor, salt, and hash together, which is everything
  /// VerifyPassword needs to check a future login attempt.
  /// </summary>
  /// <param name="password">The plain-text password to hash. Must not be null.</param>
  /// <returns>A 60-character BCrypt hash string safe to store in the database.</returns>
  public string HashPassword(string password) {
    return BCrypt.Net.BCrypt.HashPassword(password, WorkFactor);
  }

  /// <summary>
  /// Checks whether a plain-text password matches a previously stored BCrypt hash.
  ///
  /// BCrypt.Verify extracts the embedded salt from the stored hash, re-hashes the
  /// candidate password with it, and compares the results — so the caller never needs
  /// to handle the salt directly. Any exception (malformed hash, null input, library
  /// error) is caught and treated as a non-match rather than surfaced as an error,
  /// which prevents an attacker from distinguishing a bad hash from a wrong password.
  /// </summary>
  /// <param name="password">The plain-text password supplied by the user at login.</param>
  /// <param name="storedHash">The BCrypt hash retrieved from the database for this user.</param>
  /// <returns>True if the password matches the hash; false for any mismatch or error.</returns>
  public bool VerifyPassword(string password, string storedHash) {
    try {
      return BCrypt.Net.BCrypt.Verify(password, storedHash);
    }
    catch {
      // Treat any error (corrupted hash, wrong format, null, etc.) as a non-match
      return false;
    }
  }

  /// <summary>
  /// Checks that a candidate password meets VexTrainer's strength requirements before
  /// it is accepted for registration or a password change.
  ///
  /// Rules enforced (in order):
  ///   - Not null, empty, or whitespace-only
  ///   - At least 8 characters
  ///   - No more than 100 characters  (guards against BCrypt's 72-byte input limit
  ///     and prevents denial-of-service via extremely long inputs)
  ///   - At least one uppercase letter  [A-Z]
  ///   - At least one lowercase letter  [a-z]
  ///   - At least one digit             [0-9]
  ///   - At least one special character (anything that is not a letter or digit)
  ///
  /// Validation stops at the first failed rule and returns a user-facing error message
  /// describing exactly what is missing, so the client can display it directly without
  /// further interpretation. An empty ErrorMessage signals success.
  /// </summary>
  /// <param name="password">The candidate plain-text password to validate.</param>
  /// <returns>A tuple where IsValid indicates pass/fail and ErrorMessage contains a
  /// human-readable reason for any failure (empty string on success).</returns>
  public (bool IsValid, string ErrorMessage) ValidatePassword(string password) {
    if (string.IsNullOrWhiteSpace(password))
      return (false, "Password is required");

    if (password.Length < 8)
      return (false, "Password must be at least 8 characters long");

    if (password.Length > 100)
      return (false, "Password must not exceed 100 characters");

    if (!Regex.IsMatch(password, @"[A-Z]"))
      return (false, "Password must contain at least one uppercase letter");

    if (!Regex.IsMatch(password, @"[a-z]"))
      return (false, "Password must contain at least one lowercase letter");

    if (!Regex.IsMatch(password, @"[0-9]"))
      return (false, "Password must contain at least one digit");

    if (!Regex.IsMatch(password, @"[^a-zA-Z0-9]"))
      return (false, "Password must contain at least one special character");

    return (true, string.Empty);
  }
}