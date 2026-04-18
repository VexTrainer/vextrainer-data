namespace VexTrainer.Data.Models;

/// <summary>
/// Admin dashboard statistics
/// </summary>
public class AdminDashboard
{
    public int TotalRegisteredUsers { get; set; }
    public int UsersWhoTookQuizzes { get; set; }
    public int TotalQuizAttempts { get; set; }
    public int CompletedQuizzes { get; set; }
    public decimal? AverageScore { get; set; }
    public int QuizzesLast7Days { get; set; }
    public int NewUsersLast7Days { get; set; }
    public int ActiveUsers30Days { get; set; }
    public List<PopularQuiz> PopularQuizzes { get; set; } = new();
    public List<RecentUser> RecentUsers { get; set; } = new();
}

/// <summary>
/// Popular quiz item
/// </summary>
public class PopularQuiz
{
    public short QuizId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public int AttemptCount { get; set; }
    public decimal? AverageScore { get; set; }
}

/// <summary>
/// Recent user item
/// </summary>
public class RecentUser
{
    public int UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime CreatedDate { get; set; }
}

/// <summary>
/// Quiz statistics
/// </summary>
public class QuizStatistics
{
    public QuizStatisticsSummary Summary { get; set; } = new();
    public List<QuestionDifficulty> QuestionDifficulty { get; set; } = new();
}

/// <summary>
/// Quiz statistics summary
/// </summary>
public class QuizStatisticsSummary
{
    public short QuizId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public byte TotalQuestions { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public int TotalAttempts { get; set; }
    public int CompletedAttempts { get; set; }
    public decimal? AverageScore { get; set; }
    public decimal? MinScore { get; set; }
    public decimal? MaxScore { get; set; }
}

/// <summary>
/// Question difficulty analysis
/// </summary>
public class QuestionDifficulty
{
    public int QuestionId { get; set; }
    public string QuestionText { get; set; } = string.Empty;
    public int TimesAnswered { get; set; }
    public int CorrectCount { get; set; }
    public decimal CorrectPercentage { get; set; }
}

/// <summary>
/// User list item (admin)
/// </summary>
public class UserListItem
{
    public int UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string RoleName { get; set; } = string.Empty;
    public DateTime CreatedDate { get; set; }
    public DateTime? LastLoginDate { get; set; }
    public int TotalAttempts { get; set; }
    public int CompletedQuizzes { get; set; }
}

/// <summary>
/// Users list response
/// </summary>
public class UsersListResponse
{
    public List<UserListItem> Users { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
}

/// <summary>
/// Update user role request
/// </summary>
public class UpdateUserRoleRequest
{
    public byte RoleId { get; set; }
}

/// <summary>
/// Category performance
/// </summary>
public class CategoryPerformance
{
    public short CategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public int TotalQuizzes { get; set; }
    public int TotalAttempts { get; set; }
    public int CompletedAttempts { get; set; }
    public decimal? AverageScore { get; set; }
}
