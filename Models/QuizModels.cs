namespace VexTrainer.Data.Models;

/// <summary>
/// Category model
/// </summary>
public class Category
{
    public short CategoryId { get; set; }
    public short? ParentCategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public byte DisplayOrder { get; set; }
    public List<Category>? Subcategories { get; set; }
}

/// <summary>
/// Quiz model
/// </summary>
public class Quiz
{
    public short QuizId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public string? QuizDescription { get; set; }
    public byte TotalQuestions { get; set; }
    public decimal? PassingScore { get; set; }
    public byte DisplayOrder { get; set; }
    public int UserAttempts { get; set; }
    public decimal? UserBestScore { get; set; }
    public bool IsCompleted { get; set; }
}

/// <summary>
/// Quiz details
/// </summary>
public class QuizDetails
{
    public short QuizId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public string? QuizDescription { get; set; }
    public byte TotalQuestions { get; set; }
    public decimal? PassingScore { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public int UserAttempts { get; set; }
    public decimal? UserBestScore { get; set; }
}

/// <summary>
/// Start quiz attempt response
/// </summary>
public class StartQuizResponse
{
    public int AttemptId { get; set; }
    public short QuizId { get; set; }
    public DateTime StartedDate { get; set; }
    public byte TotalQuestions { get; set; }
}

/// <summary>
/// Question model
/// </summary>
public class Question
{
    public int QuestionId { get; set; }
    public byte QuestionTypeId { get; set; }
    public string QuestionType { get; set; } = string.Empty;
    public string QuestionText { get; set; } = string.Empty;
    public string? QuestionImagePath { get; set; }
    public decimal PointValue { get; set; }
    public List<Answer> Answers { get; set; } = new();
}

/// <summary>
/// Answer model
/// </summary>
public class Answer
{
    public int AnswerId { get; set; }
  public int QuestionId { get; set; }
  public string AnswerText { get; set; } = string.Empty;
    public string? AnswerImagePath { get; set; }
    public char? MatchSide { get; set; } // 'L' or 'R' for match questions
}

/// <summary>
/// Quiz questions response
/// </summary>
public class QuizQuestionsResponse
{
    public int AttemptId { get; set; }
    public List<Question> Questions { get; set; } = new();
}

/// <summary>
/// Submit answer request
/// </summary>
public class SubmitAnswerRequest
{
    public int QuestionId { get; set; }
    public string AnswerJson { get; set; } = string.Empty;
}

/// <summary>
/// Submit answer response
/// </summary>
public class SubmitAnswerResponse
{
    public bool IsCorrect { get; set; }
    public string? Explanation { get; set; }
    public string? CorrectAnswerJson { get; set; }
    public decimal CurrentScore { get; set; }
    public byte QuestionsAnswered { get; set; }
}

/// <summary>
/// Complete quiz response
/// </summary>
public class CompleteQuizResponse
{
    public int AttemptId { get; set; }
    public decimal FinalScore { get; set; }
    public byte CorrectAnswers { get; set; }
    public byte TotalQuestions { get; set; }
    public decimal? PassingScore { get; set; }  // Nullable - removed from schema
    public bool Passed { get; set; }
    public DateTime CompletedDate { get; set; }
}

/// <summary>
/// Quiz result summary
/// </summary>
public class QuizResultSummary
{
    public int AttemptId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public DateTime StartedDate { get; set; }
    public DateTime? CompletedDate { get; set; }
    public decimal? Score { get; set; }
    public byte CorrectAnswers { get; set; }
    public byte TotalQuestions { get; set; }
    public decimal? PassingScore { get; set; }  // Nullable - removed from schema
    public bool Passed { get; set; }
}

/// <summary>
/// Question result detail
/// </summary>
public class QuestionResult
{
    public int QuestionId { get; set; }
    public string QuestionText { get; set; } = string.Empty;
    public string? QuestionImagePath { get; set; }
    public string QuestionType { get; set; } = string.Empty;
    public string? UserAnswerJson { get; set; }
    public bool IsCorrect { get; set; }
    public string? Explanation { get; set; }
    public string? CorrectAnswers { get; set; } // JSON string
}

/// <summary>
/// Quiz results (detailed)
/// </summary>
public class QuizResults
{
    public QuizResultSummary Summary { get; set; } = new();
    public List<QuestionResult> Questions { get; set; } = new();
}

/// <summary>
/// Resume quiz data
/// </summary>
public class ResumeQuizData
{
    public int AttemptId { get; set; }
    public short QuizId { get; set; }
    public DateTime StartedDate { get; set; }
    public int? LastQuestionId { get; set; }
    public byte CorrectAnswers { get; set; }
    public byte TotalQuestions { get; set; }
    public decimal? Score { get; set; }
    public List<int> AnsweredQuestionIds { get; set; } = new();
}

/// <summary>
/// User dashboard statistics
/// </summary>
public class UserDashboard
{
    public int TotalQuizzesAttempted { get; set; }
    public int TotalQuizzesCompleted { get; set; }
    public decimal? AverageScore { get; set; }
    public int TotalCorrectAnswers { get; set; }
    public List<RecentAttempt> RecentAttempts { get; set; } = new();
}

/// <summary>
/// Recent attempt summary
/// </summary>
public class RecentAttempt
{
    public int AttemptId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public decimal? Score { get; set; }
    public DateTime? CompletedDate { get; set; }
    public bool IsCompleted { get; set; }
}

/// <summary>
/// Quiz history item
/// </summary>
public class QuizHistoryItem
{
    public int AttemptId { get; set; }
    public short QuizId { get; set; }
    public string QuizTitle { get; set; } = string.Empty;
    public string CategoryName { get; set; } = string.Empty;
    public DateTime StartedDate { get; set; }
    public DateTime? CompletedDate { get; set; }
    public decimal? Score { get; set; }
    public bool IsCompleted { get; set; }
}

/// <summary>
/// Quiz history response
/// </summary>
public class QuizHistoryResponse
{
    public List<QuizHistoryItem> Attempts { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
}
