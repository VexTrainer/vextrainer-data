using Dapper;
using Microsoft.Data.SqlClient;
using System.Data;
using VexTrainer.Data.Models;
namespace VexTrainer.Data.Services;

/// <summary>
/// AdminService is the database layer for all administrative operations in VexTrainer.
/// It uses Dapper to call SQL Server stored procedures and returns standardized
/// ApiResponse objects to the caller.
///
/// This service is intended for privileged back-office use only — access to every
/// endpoint it backs should be gated by an Admin role check at the controller or
/// middleware level. No user-facing quiz or lesson logic lives here.
///
/// Responsibilities covered:
///   - Platform-wide statistics and activity summaries (admin dashboard)
///   - Per-quiz performance and per-question difficulty analysis
///   - User listing, role management, and account deactivation
///   - Category-level performance reporting across all users
///
/// Note: this service takes no @user_id on most calls because it operates on
/// platform-wide data rather than a single user's session. The two exceptions
/// (UpdateUserRoleAsync, DeactivateUserAsync) take a @user_id that identifies
/// the target user being managed, not the admin performing the action.
/// </summary>
public class AdminService {
  private readonly string _connectionString;

  public AdminService(string connectionString) {
    _connectionString = connectionString;
  }

  /// <summary>
  /// Returns the platform-wide statistics shown on the admin home dashboard.
  ///
  /// The stored procedure emits four result sets in a single round trip:
  ///   1. Aggregate stats row (total users, total quizzes taken, overall pass rate,
  ///      etc.) → AdminDashboard
  ///   2. Most popular quizzes by attempt count → List&lt;PopularQuiz&gt;
  ///   3. Most recently registered users → List&lt;RecentUser&gt;
  ///   4. A single dynamic row containing active_users_30_days (a scalar value
  ///      returned as its own result set so the stored procedure can compute it
  ///      independently) → hydrated into AdminDashboard.ActiveUsers30Days
  ///
  /// All four sets are assembled into a single AdminDashboard object before returning.
  /// If the stats row is missing, an empty AdminDashboard is returned so the caller
  /// always has a valid object to bind against.
  ///
  /// IMPORTANT: Result sets must be read in order — stats, popular quizzes, recent
  /// users, active users — matching the sequence the stored procedure emits them.
  ///
  /// Stored procedure : sp_GetAdminDashboard
  /// Inputs           : (none)
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) AdminDashboard stats row
  ///                    (2) List&lt;PopularQuiz&gt;
  ///                    (3) List&lt;RecentUser&gt;
  ///                    (4) Dynamic row with active_users_30_days
  /// </summary>
  public async Task<ApiResponse<AdminDashboard>> GetAdminDashboardAsync() {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_GetAdminDashboard", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the exact order the stored procedure emits them
    var stats = await multi.ReadFirstOrDefaultAsync<AdminDashboard>();
    var popularQuizzes = (await multi.ReadAsync<PopularQuiz>()).ToList();
    var recentUsers = (await multi.ReadAsync<RecentUser>()).ToList();
    var activeUsers = await multi.ReadFirstOrDefaultAsync<dynamic>();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (stats != null) {
      stats.PopularQuizzes = popularQuizzes;
      stats.RecentUsers = recentUsers;
      stats.ActiveUsers30Days = activeUsers?.active_users_30_days ?? 0;
    }

    return new ApiResponse<AdminDashboard> {
      Success = resultCode == 0,
      Data = stats ?? new AdminDashboard(),   // never null — caller can always bind
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns detailed performance statistics for a specific quiz, intended for
  /// an admin drill-down view on quiz health and difficulty calibration.
  ///
  /// The stored procedure returns two result sets in a single round trip:
  ///   1. A summary row (total attempts, pass rate, average score, average completion
  ///      time, etc.) → QuizStatisticsSummary
  ///   2. A per-question difficulty breakdown (attempt count, correct rate) showing
  ///      which questions are too easy or too hard → List&lt;QuestionDifficulty&gt;
  ///
  /// Both sets are assembled into a single QuizStatistics object. If the summary row
  /// is missing (invalid quiz ID), an empty QuizStatisticsSummary is substituted.
  ///
  /// Stored procedure : sp_GetQuizStatistics
  /// Inputs           : @quiz_id
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) QuizStatisticsSummary row
  ///                    (2) List&lt;QuestionDifficulty&gt;
  /// </summary>
  public async Task<ApiResponse<QuizStatistics>> GetQuizStatisticsAsync(short quizId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@quiz_id", quizId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_GetQuizStatistics", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the exact order the stored procedure emits them
    var summary = await multi.ReadFirstOrDefaultAsync<QuizStatisticsSummary>();
    var questionDifficulty = (await multi.ReadAsync<QuestionDifficulty>()).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<QuizStatistics> {
      Success = resultCode == 0,
      Data = new QuizStatistics {
        Summary = summary ?? new QuizStatisticsSummary(),   // never null — caller can always bind
        QuestionDifficulty = questionDifficulty
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns a paginated list of all registered users on the platform for the
  /// admin user-management screen.
  ///
  /// Pagination is handled entirely server-side: the caller supplies a 1-based page
  /// number and page size, and the stored procedure returns only that slice. The total
  /// user count is returned as an OUTPUT parameter so the client can calculate total
  /// pages without a separate COUNT query. The default page size is 50 (larger than
  /// the 20 used in the user-facing quiz history) to suit an admin list view.
  ///
  /// Stored procedure : sp_GetAllUsers
  /// Inputs           : @page, @page_size
  /// Outputs          : @total_count, @result_code, @result_message
  /// Result set       : List&lt;UserListItem&gt; (one page of results)
  /// </summary>
  public async Task<ApiResponse<UsersListResponse>> GetAllUsersAsync(int page = 1, int pageSize = 50) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@page", page);
    parameters.Add("@page_size", pageSize);
    parameters.Add("@total_count", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var users = (await connection.QueryAsync<UserListItem>("sp_GetAllUsers", parameters, commandType: CommandType.StoredProcedure)).ToList();

    var totalCount = parameters.Get<int>("@total_count");
    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<UsersListResponse> {
      Success = resultCode == 0,
      Data = new UsersListResponse {
        Users = users,
        TotalCount = totalCount,
        Page = page,
        PageSize = pageSize
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Changes the role assigned to a user account, for example promoting a user to
  /// Admin or demoting an Admin back to User.
  ///
  /// The @role_id is a byte-sized foreign key matching the roles table (e.g., 1 = User,
  /// 2 = Admin). Role validation and permission checks are the stored procedure's
  /// responsibility. The controller should independently verify that the requesting
  /// admin cannot demote themselves or another admin above their own privilege level.
  ///
  /// Stored procedure : sp_UpdateUserRole
  /// Inputs           : @user_id (the target user), @role_id (the new role)
  /// Outputs          : @result_code, @result_message
  /// </summary>
  public async Task<ApiResponse<object>> UpdateUserRoleAsync(int userId, byte roleId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@user_id", userId);
    parameters.Add("@role_id", roleId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("sp_UpdateUserRole", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<object> {
      Success = resultCode == 0,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Marks a user account as inactive, preventing them from logging in without
  /// permanently deleting their data or quiz history.
  ///
  /// This is a soft deactivation — the account row and all associated records remain
  /// in the database, so the action can be reversed by re-activating the account via
  /// a direct database update or a future admin endpoint. It is distinct from the
  /// user-initiated account deletion flow (AuthService), which anonymizes PII.
  ///
  /// Stored procedure : sp_DeactivateUser
  /// Inputs           : @user_id (the target user)
  /// Outputs          : @result_code, @result_message
  /// </summary>
  public async Task<ApiResponse<object>> DeactivateUserAsync(int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("sp_DeactivateUser", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<object> {
      Success = resultCode == 0,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns aggregate pass rates, average scores, and attempt counts grouped by
  /// quiz category across all users — giving admins a high-level view of which areas
  /// of the curriculum students find easy or difficult.
  ///
  /// This is a platform-wide report with no user filter, so no @user_id is passed.
  /// The results are typically used to identify categories that may need more quiz
  /// content, easier introductory questions, or revised explanations.
  ///
  /// Stored procedure : sp_GetCategoryPerformance
  /// Inputs           : (none)
  /// Outputs          : @result_code, @result_message
  /// Result set       : List&lt;CategoryPerformance&gt;
  /// </summary>
  public async Task<ApiResponse<List<CategoryPerformance>>> GetCategoryPerformanceAsync() {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var categories = (await connection.QueryAsync<CategoryPerformance>("sp_GetCategoryPerformance", parameters, commandType: CommandType.StoredProcedure)).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<List<CategoryPerformance>> {
      Success = resultCode == 0,
      Data = categories,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }
}