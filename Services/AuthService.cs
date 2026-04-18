using Dapper;
using Microsoft.Data.SqlClient;
using System.Data;
using VexTrainer.Data.Models;
namespace VexTrainer.Data.Services;

/// <summary>
/// AuthService is the database layer for all authentication and account management operations
/// in VexTrainer. It uses Dapper to call SQL Server stored procedures and returns standardized
/// ApiResponse objects to the caller.
///
/// Dependencies injected at construction:
///   - PasswordService   : BCrypt hashing and password strength validation (runs in .NET, not SQL)
///   - ITokenService     : JWT access-token and refresh-token generation
///   - connectionString  : SQL Server connection used for every database call
///
/// General pattern used throughout this class:
///   1. Build a DynamicParameters object with input values and typed OUTPUT placeholders.
///   2. Call a stored procedure via Dapper's ExecuteAsync.
///   3. Read the OUTPUT parameters (@result_code, @result_message, and any data outputs).
///   4. Return an ApiResponse whose Success flag is driven by result_code == 0.
/// </summary>
public class AuthService
{
    private readonly string _connectionString;
    private readonly PasswordService _passwordService;
    private readonly ITokenService _tokenService;

    public AuthService(
        string connectionString,
        PasswordService passwordService,
        ITokenService tokenService)
    {
        _connectionString = connectionString;
        _passwordService = passwordService;
        _tokenService = tokenService;
    }

    /// <summary>
    /// Step 1 of the account-deletion flow.
    ///
    /// Generates a cryptographically secure, URL-safe token (48 random bytes → Base64, symbols
    /// replaced so it can travel safely in a URL), then calls sp_RequestAccountDeletion to store
    /// that token against the user's record and return the email address on file.
    ///
    /// The caller is expected to email the token link to the user. If no account matches the
    /// supplied email, the stored procedure still returns result_code = 0 — and this method always
    /// returns Success = true — so that an attacker cannot tell whether a given email is registered
    /// (anti-enumeration protection). The Data payload is non-null only when a real account was
    /// found; the controller checks Data before sending the email.
    ///
    /// Stored procedure : sp_RequestAccountDeletion
    /// Inputs           : @email, @token, @ip_address
    /// Outputs          : @user_id, @user_email, @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<AccountDeletionRequestResult>> RequestAccountDeletionAsync(
        string email, string ipAddress)
    {
        // Generate a cryptographically secure URL-safe token
        var tokenBytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(48);
        var token = Convert.ToBase64String(tokenBytes)
            .Replace("+", "-").Replace("/", "_").Replace("=", "");

        using var connection = new SqlConnection(_connectionString);

        var parameters = new DynamicParameters();
        parameters.Add("@email", email.Trim());
        parameters.Add("@token", token);
        parameters.Add("@ip_address", ipAddress);
        parameters.Add("@user_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@user_email", dbType: DbType.String, size: 254, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_RequestAccountDeletion", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");
        var userId = parameters.Get<int?>("@user_id");
        var userEmail = parameters.Get<string?>("@user_email");

        return new ApiResponse<AccountDeletionRequestResult>
        {
            Success = true,   // always true — generic message prevents enumeration
            Message = resultMessage,
            ResultCode = resultCode,
            Data = userId.HasValue
                ? new AccountDeletionRequestResult
                {
                    UserId = userId.Value,
                    UserEmail = userEmail,
                    Token = token
                }
                : null
        };
    }

    /// <summary>
    /// Step 2 of the account-deletion flow.
    ///
    /// The user clicks the link from the deletion email, which carries the one-time token.
    /// This method passes that token to sp_ConfirmAccountDeletion, which validates the token
    /// (checks expiry, marks it used) and permanently anonymizes the account row — replacing
    /// PII fields with placeholder values so no personal data remains.
    ///
    /// On success, the deleted email address is returned in Data so the caller can send a
    /// goodbye/confirmation email before the address is overwritten. On failure (bad token,
    /// already used, expired) Success = false and Data is null.
    ///
    /// Stored procedure : sp_ConfirmAccountDeletion
    /// Inputs           : @token
    /// Outputs          : @deleted_email, @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<string>> ConfirmAccountDeletionAsync(string token)
    {
        using var connection = new SqlConnection(_connectionString);

        var parameters = new DynamicParameters();
        parameters.Add("@token", token);
        parameters.Add("@deleted_email", dbType: DbType.String, size: 254, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_ConfirmAccountDeletion", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");
        var deletedEmail = parameters.Get<string?>("@deleted_email");

        return new ApiResponse<string>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode,
            Data = deletedEmail   // null if failed — caller checks Success first
        };
    }

    /// <summary>
    /// Registers a new user account.
    ///
    /// Password strength is validated in .NET first (before touching the database). If the
    /// password passes, it is BCrypt-hashed and passed — along with username, email, and device
    /// info — to sp_RegisterUser, which creates the account row and returns the new user ID.
    ///
    /// On success, a JWT access token and a refresh token are generated immediately so the user
    /// is logged in right away without a separate login call. A session row is also written via
    /// CreateSessionAsync.
    ///
    /// Stored procedure : sp_RegisterUser
    /// Inputs           : @user_name, @email, @password_hash, @device_info
    /// Outputs          : @new_user_id, @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<AuthResponse>> RegisterAsync(RegisterRequest request, string deviceInfo)
    {
        // Validate password strength before hitting the database
        var (isValid, errorMessage) = _passwordService.ValidatePassword(request.Password);
        if (!isValid)
        {
            return new ApiResponse<AuthResponse>
            {
                Success = false,
                Message = errorMessage,
                ResultCode = 1
            };
        }

        var passwordHash = _passwordService.HashPassword(request.Password);

        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_name", request.UserName);
        parameters.Add("@email", request.Email);
        //parameters.Add("@phone", request.Phone);
        parameters.Add("@password_hash", passwordHash);
        parameters.Add("@device_info", deviceInfo);
        parameters.Add("@new_user_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_RegisterUser", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        if (resultCode != 0)
        {
            return new ApiResponse<AuthResponse>
            {
                Success = false,
                Message = resultMessage,
                ResultCode = resultCode
            };
        }

        var userId = parameters.Get<int>("@new_user_id");

        // Generate tokens and create the initial session so the user is logged in immediately
        var (token, expiryDate) = _tokenService.GenerateAccessToken(userId, request.UserName, "User", request.Email);
        var refreshToken = _tokenService.GenerateRefreshToken();
        await CreateSessionAsync(userId, token, refreshToken, expiryDate, deviceInfo);

        return new ApiResponse<AuthResponse>
        {
            Success = true,
            Data = new AuthResponse
            {
                UserId = userId,
                UserName = request.UserName,
                Email = request.Email,
                Token = token,
                RefreshToken = refreshToken,
                ExpiryDate = expiryDate,
                RoleName = "User"
            },
            Message = resultMessage,
            ResultCode = 0
        };
    }

    /// <summary>
    /// Authenticates an existing user and starts a new session.
    ///
    /// Login is intentionally split across .NET and SQL to keep the BCrypt hash comparison
    /// out of the database:
    ///   1. sp_GetUserForLogin fetches the stored password hash and user profile by username
    ///      or email (the @identifier field accepts either).
    ///   2. BCrypt verification runs in .NET against the retrieved hash.
    ///   3. On a match, a JWT access token and refresh token are generated.
    ///   4. A session row is written via CreateSessionAsync.
    ///
    /// Both "user not found" and "wrong password" return the same generic "Invalid credentials"
    /// message to prevent username enumeration.
    ///
    /// Stored procedure : sp_GetUserForLogin
    /// Inputs           : @identifier  (username or email)
    /// Outputs          : @user_id, @user_name, @email, @password_hash, @role_id,
    ///                    @role_name, @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<AuthResponse>> LoginAsync(LoginRequest request, string deviceInfo)
    {
        using var connection = new SqlConnection(_connectionString);

        // Step 1: Fetch the user record (including the stored hash) from the database
        var parameters = new DynamicParameters();
        parameters.Add("@identifier", request.Identifier);
        parameters.Add("@user_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@user_name", dbType: DbType.String, size: 24, direction: ParameterDirection.Output);
        parameters.Add("@email", dbType: DbType.String, size: 254, direction: ParameterDirection.Output);
        parameters.Add("@password_hash", dbType: DbType.String, size: 200, direction: ParameterDirection.Output);
        parameters.Add("@role_id", dbType: DbType.Byte, direction: ParameterDirection.Output);
        parameters.Add("@role_name", dbType: DbType.String, size: 32, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_GetUserForLogin", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");

        // If user not found, return generic error (security best practice — prevents enumeration)
        if (resultCode != 0)
        {
            return new ApiResponse<AuthResponse>
            {
                Success = false,
                Message = "Invalid credentials",
                ResultCode = 1
            };
        }

        // Step 2: Verify the supplied password against the stored BCrypt hash in .NET
        var userId = parameters.Get<int>("@user_id");
        var userName = parameters.Get<string>("@user_name");
        var email = parameters.Get<string>("@email");
        var storedPasswordHash = parameters.Get<string>("@password_hash");
        var roleName = parameters.Get<string>("@role_name");

        if (!_passwordService.VerifyPassword(request.Password, storedPasswordHash))
        {
            return new ApiResponse<AuthResponse>
            {
                Success = false,
                Message = "Invalid credentials",
                ResultCode = 1
            };
        }

        // Step 3: Generate JWT and refresh tokens
        var (token, expiryDate) = _tokenService.GenerateAccessToken(userId, userName, roleName);
        var refreshToken = _tokenService.GenerateRefreshToken();

        // Step 4: Persist the session to the database
        await CreateSessionAsync(userId, token, refreshToken, expiryDate, deviceInfo);

        return new ApiResponse<AuthResponse>
        {
            Success = true,
            Data = new AuthResponse
            {
                UserId = userId,
                UserName = userName,
                Email = email,
                Token = token,
                RefreshToken = refreshToken,
                ExpiryDate = expiryDate,
                RoleName = roleName
            },
            Message = "Login successful",
            ResultCode = 0
        };
    }

    /// <summary>
    /// Issues a new access token using a valid refresh token.
    ///
    /// Because the refresh token alone does not carry user identity, a two-pass approach is
    /// used: a temporary placeholder token is generated first so all three values (new token,
    /// new refresh token, new expiry) can be passed atomically to sp_RefreshToken, which
    /// validates the old refresh token, swaps it for the new one in the session row, and
    /// returns the user's ID and username. The correct final JWT is then regenerated with
    /// those values and returned to the caller.
    ///
    /// Note: email is not returned by the refresh flow — the Email field in the response is
    /// left as an empty string.
    ///
    /// Stored procedure : sp_RefreshToken
    /// Inputs           : @refresh_token, @new_token, @new_refresh_token, @new_expiry_date
    /// Outputs          : @user_id, @user_name, @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<AuthResponse>> RefreshTokenAsync(string refreshToken)
    {
        // Pre-generate placeholder tokens; they are passed to the SP so it can atomically
        // swap the session. The final token is regenerated below once we have the user info.
        var (newToken, newExpiryDate) = _tokenService.GenerateAccessToken(0, "", "");
        var newRefreshToken = _tokenService.GenerateRefreshToken();

        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@refresh_token", refreshToken);
        parameters.Add("@new_token", newToken);
        parameters.Add("@new_refresh_token", newRefreshToken);
        parameters.Add("@new_expiry_date", newExpiryDate);
        parameters.Add("@user_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@user_name", dbType: DbType.String, size: 24, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_RefreshToken", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        if (resultCode != 0)
        {
            return new ApiResponse<AuthResponse>
            {
                Success = false,
                Message = resultMessage,
                ResultCode = resultCode
            };
        }

        var userId = parameters.Get<int>("@user_id");
        var userName = parameters.Get<string>("@user_name");

        // Regenerate the token with the real user identity now that we have it
        (newToken, newExpiryDate) = _tokenService.GenerateAccessToken(userId, userName, "User");

        return new ApiResponse<AuthResponse>
        {
            Success = true,
            Data = new AuthResponse
            {
                UserId = userId,
                UserName = userName,
                Email = "",   // Not returned by the refresh flow
                Token = newToken,
                RefreshToken = newRefreshToken,
                ExpiryDate = newExpiryDate,
                RoleName = "User"
            },
            Message = resultMessage,
            ResultCode = 0
        };
    }

    /// <summary>
    /// Logs out the user by invalidating their current session token.
    ///
    /// Passes the JWT access token to sp_LogoutUser, which marks the matching session row as
    /// inactive (or deletes it). After this call the token is no longer accepted by the API.
    ///
    /// Stored procedure : sp_LogoutUser
    /// Inputs           : @token
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> LogoutAsync(string token)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@token", token);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_LogoutUser", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<object>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Updates the email address and phone number on the user's profile.
    ///
    /// Passes the new values to sp_UpdateUserProfile. The stored procedure is responsible for
    /// any uniqueness checks (e.g., duplicate email) and returns a descriptive message if the
    /// update cannot be applied.
    ///
    /// Stored procedure : sp_UpdateUserProfile
    /// Inputs           : @user_id, @email, @phone
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> UpdateProfileAsync(int userId, UpdateProfileRequest request)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@email", request.Email);
        parameters.Add("@phone", request.Phone);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_UpdateUserProfile", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<object>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Changes the authenticated user's password.
    ///
    /// Three checks are performed before writing anything:
    ///   1. The new password must pass strength validation (in .NET).
    ///   2. sp_GetUserPasswordHash fetches the current BCrypt hash from the database.
    ///   3. The supplied old password is verified against that hash in .NET.
    ///
    /// Only if all three pass is the new hash written via sp_UpdatePassword. This approach
    /// keeps BCrypt entirely in .NET and ensures the user must know their current password
    /// to complete the change (not just hold a valid session token).
    ///
    /// Stored procedures : sp_GetUserPasswordHash, sp_UpdatePassword
    ///
    /// sp_GetUserPasswordHash
    ///   Inputs  : @user_id
    ///   Outputs : @password_hash, @result_code
    ///
    /// sp_UpdatePassword
    ///   Inputs  : @user_id, @new_password_hash
    ///   Outputs : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> ChangePasswordAsync(int userId, ChangePasswordRequest request)
    {
        // Validate new password strength before touching the database
        var (isValid, errorMessage) = _passwordService.ValidatePassword(request.NewPassword);
        if (!isValid)
        {
            return new ApiResponse<object>
            {
                Success = false,
                Message = errorMessage,
                ResultCode = 1
            };
        }

        // Fetch the current hash so we can verify the old password in .NET
        using var connection = new SqlConnection(_connectionString);
        var getUserParams = new DynamicParameters();
        getUserParams.Add("@user_id", userId);
        getUserParams.Add("@password_hash", dbType: DbType.String, size: 200, direction: ParameterDirection.Output);
        getUserParams.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_GetUserPasswordHash", getUserParams, commandType: CommandType.StoredProcedure);

        var getUserResultCode = getUserParams.Get<int>("@result_code");
        if (getUserResultCode != 0)
        {
            return new ApiResponse<object>
            {
                Success = false,
                Message = "User not found",
                ResultCode = 1
            };
        }

        var storedPasswordHash = getUserParams.Get<string>("@password_hash");

        // Verify the caller knows the current password before allowing the change
        if (!_passwordService.VerifyPassword(request.OldPassword, storedPasswordHash))
        {
            return new ApiResponse<object>
            {
                Success = false,
                Message = "Current password is incorrect",
                ResultCode = 1
            };
        }

        // Hash the new password and persist it
        var newPasswordHash = _passwordService.HashPassword(request.NewPassword);
        var updateParams = new DynamicParameters();
        updateParams.Add("@user_id", userId);
        updateParams.Add("@new_password_hash", newPasswordHash);
        updateParams.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        updateParams.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_UpdatePassword", updateParams, commandType: CommandType.StoredProcedure);

        var resultCode = updateParams.Get<int>("@result_code");
        var resultMessage = updateParams.Get<string>("@result_message");

        return new ApiResponse<object>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Private helper — writes a new session record to the database.
    ///
    /// Called internally by RegisterAsync and LoginAsync immediately after tokens are
    /// generated. Stores the JWT, refresh token, expiry, and device info so the API can
    /// validate tokens on subsequent requests and enforce single-device or multi-device
    /// session policies at the database level.
    ///
    /// Stored procedure : sp_CreateSession
    /// Inputs           : @user_id, @token, @refresh_token, @expiry_date, @device_info
    /// Outputs          : @session_id, @result_code, @result_message
    ///                    (output values are not read; failures are silent at this layer)
    /// </summary>
    private async Task CreateSessionAsync(int userId, string token, string refreshToken, DateTime expiryDate, string deviceInfo)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@token", token);
        parameters.Add("@refresh_token", refreshToken);
        parameters.Add("@expiry_date", expiryDate);
        parameters.Add("@device_info", deviceInfo);
        parameters.Add("@session_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_CreateSession", parameters, commandType: CommandType.StoredProcedure);
    }

    /// <summary>
    /// Activates a user account after they click the email-confirmation link.
    ///
    /// Token validation is handled by the controller before this method is called; by the
    /// time execution reaches here, the email address has already been verified as belonging
    /// to the correct one-time link. sp_ActivateUser flips the account's status from
    /// "pending" to "active" so the user can log in.
    ///
    /// Stored procedure : sp_ActivateUser
    /// Inputs           : @email
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> ActivateUserAsync(string email)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@email", email);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_ActivateUser", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<object>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Sets a new password for a user who has forgotten their current one.
    ///
    /// This method is the second half of the forgot-password flow. The controller handles
    /// the first half: validating the one-time reset token from the email link. Once the
    /// controller confirms the token is valid, it calls this method with the verified email
    /// and the user's chosen new password.
    ///
    /// Password strength is validated in .NET first. If it passes, the password is BCrypt-
    /// hashed here and then written to the database via sp_ResetPassword, which updates the
    /// hash and should also invalidate any outstanding reset tokens for that account.
    ///
    /// Stored procedure : sp_ResetPassword
    /// Inputs           : @email, @password_hash
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> ResetPasswordByEmailAsync(string email, string newPassword)
    {
        // Validate password strength before hitting the database
        var (isValid, errorMessage) = _passwordService.ValidatePassword(newPassword);
        if (!isValid)
        {
            return new ApiResponse<object>
            {
                Success = false,
                Message = errorMessage,
                ResultCode = 1
            };
        }

        var passwordHash = _passwordService.HashPassword(newPassword);

        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@email", email);
        parameters.Add("@password_hash", passwordHash);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_ResetPassword", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<object>
        {
            Success = resultCode == 0,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }
}