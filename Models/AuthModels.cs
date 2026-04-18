namespace VexTrainer.Data.Models;

/// <summary>
/// Standard API response wrapper
/// </summary>
public class ApiResponse<T>
{
    public bool Success { get; set; }
    public T? Data { get; set; }
    public string? Message { get; set; }
    public int ResultCode { get; set; }
}

/// <summary>
/// Error response
/// </summary>
public class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public int StatusCode { get; set; }
}

/// <summary>
/// Register request
/// </summary>
public class RegisterRequest
{
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string Password { get; set; } = string.Empty;
}

/// <summary>
/// Login request
/// </summary>
public class LoginRequest
{
    public string Identifier { get; set; } = string.Empty; // username, email, or phone
    public string Password { get; set; } = string.Empty;
}

/// <summary>
/// Refresh token request
/// </summary>
public class RefreshTokenRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

/// <summary>
/// Authentication response
/// </summary>
public class AuthResponse
{
    public int UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Token { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public DateTime ExpiryDate { get; set; }
    public string RoleName { get; set; } = string.Empty;
}

/// <summary>
/// Update profile request
/// </summary>
public class UpdateProfileRequest
{
    public string Email { get; set; } = string.Empty;
    public string? Phone { get; set; }
}

/// <summary>
/// Change password request
/// </summary>
public class ChangePasswordRequest
{
    public string OldPassword { get; set; } = string.Empty;
    public string NewPassword { get; set; } = string.Empty;
}

public class AccountDeletionRequestResult {
  public int UserId { get; set; }
  public string? UserEmail { get; set; }
  public string Token { get; set; } = string.Empty;
}
