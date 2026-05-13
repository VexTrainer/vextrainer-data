namespace VexTrainer.Data.Models;

/// <summary>
/// Module model (top-level grouping)
/// </summary>
public class Module {
  public short ModuleId { get; set; }
  public string ModuleName { get; set; } = string.Empty;
  public string? Description { get; set; }
  public byte DisplayOrder { get; set; }
  public int LessonCount { get; set; }
  public int CompletedLessons { get; set; }
}

  /// <summary>
  /// Lesson model with read status
  /// </summary>
//  public class Lesson
//{
//    public short LessonId { get; set; }
//    public short ModuleId { get; set; }
//    public string LessonTitle { get; set; } = string.Empty;
//    public string FileName { get; set; } = string.Empty;
//    public short DisplayOrder { get; set; }
//    public bool IsRead { get; set; }
//    public DateTime? ReadDate { get; set; }
//    public int TotalTopics { get; set; }
//}

public class Lesson {
  public short LessonId { get; set; }
  public string LessonTitle { get; set; } = string.Empty;
  public short DisplayOrder { get; set; }
  public int TopicCount { get; set; }
  public int CompletedTopics { get; set; }
  public bool IsCompleted { get; set; }
}

/// <summary>
/// Lesson details
/// </summary>
public class LessonDetails
{
    public short LessonId { get; set; }
    public short ModuleId { get; set; }
    public string LessonTitle { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string ModuleName { get; set; } = string.Empty;
    public bool IsRead { get; set; }
    public DateTime? ReadDate { get; set; }
    public int TotalTopics { get; set; }
}

/// <summary>
/// Topic/page model with read status
/// </summary>
public class Topic
{
    public int TopicId { get; set; }
    public string TopicTitle { get; set; } = string.Empty;
    public byte HeadingLevel { get; set; }  // 3 for H3, 4 for H4
    public int? ParentTopicId { get; set; }
    public short DisplayOrder { get; set; }
    public bool IsRead { get; set; }
    public DateTime? ReadDate { get; set; }
}

/// <summary>
/// Reading progress summary
/// </summary>
public class ReadingProgress
{
    public int TotalLessons { get; set; }
    public int LessonsRead { get; set; }
    public int TotalTopics { get; set; }
    public int TopicsRead { get; set; }
    public decimal LessonsProgressPercent => TotalLessons > 0 ? (decimal)LessonsRead / TotalLessons * 100 : 0;
    public decimal TopicsProgressPercent => TotalTopics > 0 ? (decimal)TopicsRead / TotalTopics * 100 : 0;
    public List<RecentLesson> RecentLessons { get; set; } = new();
    public List<ModuleProgress> ModuleProgress { get; set; } = new();
}

/// <summary>
/// Recent lesson item
/// </summary>
public class RecentLesson
{
    public string LessonTitle { get; set; } = string.Empty;
    public string ModuleName { get; set; } = string.Empty;
    public DateTime ReadDate { get; set; }
}

/// <summary>
/// Module progress
/// </summary>
public class ModuleProgress
{
    public short ModuleId { get; set; }
    public string ModuleName { get; set; } = string.Empty;
    public int TotalLessons { get; set; }
    public int LessonsRead { get; set; }
    public decimal ProgressPercent => TotalLessons > 0 ? (decimal)LessonsRead / TotalLessons * 100 : 0;
}

/// <summary>
/// All lessons with progress (for browsing/search)
/// </summary>
public class LessonWithProgress
{
    public short LessonId { get; set; }
    public string LessonTitle { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public short ModuleId { get; set; }
    public string ModuleName { get; set; } = string.Empty;
    public bool IsRead { get; set; }
    public int TotalTopics { get; set; }
    public int TopicsRead { get; set; }
    public decimal TopicsProgressPercent => TotalTopics > 0 ? (decimal)TopicsRead / TotalTopics * 100 : 0;
}

/// <summary>
/// Full curriculum tree returned by a single round trip to
/// sp_GetAllModulesLessonsTopics. The three lists are flat (not
/// nested); the client groups topics by LessonId and lessons by
/// ModuleId to build the display hierarchy.
/// </summary>
public class ModulesLessonsTopicsTree {
  public List<ModuleNode> Modules { get; set; } = new();
  public List<LessonNode> Lessons { get; set; } = new();
  public List<TopicNode> Topics { get; set; } = new();
}

/// <summary>
/// One row from result set 1 (Modules).
/// </summary>
public class ModuleNode {
  public short ModuleId { get; set; }
  public string ModuleName { get; set; } = string.Empty;
  public byte DisplayOrder { get; set; }
}

/// <summary>
/// One row from result set 2 (Lessons with progress).
/// </summary>
public class LessonNode {
  public short LessonId { get; set; }
  public short ModuleId { get; set; }
  public string LessonTitle { get; set; } = string.Empty;
  public string FileName { get; set; } = string.Empty;
  public short DisplayOrder { get; set; }
  public bool IsRead { get; set; }
  public int TotalTopics { get; set; }
  public int TopicsRead { get; set; }
}

/// <summary>
/// One row from result set 3 (Topics, navigable only — H3/H4
/// always, plus H2 when its lesson has no H3 child).
/// </summary>
public class TopicNode {
  public int TopicId { get; set; }
  public short LessonId { get; set; }
  public string TopicTitle { get; set; } = string.Empty;
  public byte HeadingLevel { get; set; }
  public int? ParentTopicId { get; set; }
  public short DisplayOrder { get; set; }
  public bool IsRead { get; set; }
}


/// <summary>
/// Aggregate web-dashboard payload assembled from
/// sp_GetUserWebDashboard's six result sets. The mobile app is
/// expected to have its own analogous model when needed.
/// </summary>
public class UserWebDashboard {
  public DashboardStats Stats { get; set; } = new();
  public List<ContinueLearningItem> ContinueLearning { get; set; } = new();
  public UpNextItem? UpNext { get; set; }
  public List<RecentActivityItem> RecentActivity { get; set; } = new();
  public List<ModuleProgress> ModuleProgress { get; set; } = new();
  public LastQuizAttempt? LastQuizAttempt { get; set; }
}

/// <summary>
/// Single-row stats from result set 1.
/// Percent fields are computed client-side from the raw counts.
/// </summary>
public class DashboardStats {
  public int TotalModules { get; set; }
  public int CompletedModules { get; set; }
  public int TotalLessons { get; set; }
  public int CompletedLessons { get; set; }
  public int TotalTopics { get; set; }
  public int TopicsRead { get; set; }
  public int QuizzesAttempted { get; set; }
  public int QuizzesCompleted { get; set; }
  public decimal AverageQuizScore { get; set; }
  public decimal BestQuizScore { get; set; }
  public int ReadingStreak { get; set; }

  public int ModulesProgressPercent =>
      TotalModules > 0 ? (int)System.Math.Round((double)CompletedModules / TotalModules * 100) : 0;

  public int LessonsProgressPercent =>
      TotalLessons > 0 ? (int)System.Math.Round((double)CompletedLessons / TotalLessons * 100) : 0;

  public int TopicsProgressPercent =>
      TotalTopics > 0 ? (int)System.Math.Round((double)TopicsRead / TotalTopics * 100) : 0;
}

/// <summary>
/// One row from result set 2 — a lesson the user has started
/// but not finished, paired with the next unread navigable topic.
/// </summary>
public class ContinueLearningItem {
  public short LessonId { get; set; }
  public string LessonTitle { get; set; } = string.Empty;
  public short ModuleId { get; set; }
  public string ModuleName { get; set; } = string.Empty;
  public int TopicsRead { get; set; }
  public int TotalTopics { get; set; }
  public int NextTopicId { get; set; }
  public string NextTopicTitle { get; set; } = string.Empty;
}

/// <summary>
/// Result set 3 — the first untouched lesson in curriculum order,
/// with its first navigable topic. Used when ContinueLearning is empty.
/// </summary>
public class UpNextItem {
  public short LessonId { get; set; }
  public string LessonTitle { get; set; } = string.Empty;
  public short ModuleId { get; set; }
  public string ModuleName { get; set; } = string.Empty;
  public int FirstTopicId { get; set; }
  public string FirstTopicTitle { get; set; } = string.Empty;
}

/// <summary>
/// One row from result set 4 — a recently read topic with its
/// surrounding context (lesson + module) and the timestamp.
/// </summary>
public class RecentActivityItem {
  public int TopicId { get; set; }
  public string TopicTitle { get; set; } = string.Empty;
  public short LessonId { get; set; }
  public string LessonTitle { get; set; } = string.Empty;
  public short ModuleId { get; set; }
  public string ModuleName { get; set; } = string.Empty;
  public DateTime ReadDate { get; set; }   // UTC
}

/// <summary>
/// Result set 6 — the user's most recent quiz attempt, completed
/// or still in progress. Null when the user has never attempted a quiz.
/// </summary>
public class LastQuizAttempt {
  public int AttemptId { get; set; }
  public short QuizId { get; set; }
  public string QuizTitle { get; set; } = string.Empty;
  public decimal? Score { get; set; }
  public DateTime StartedDate { get; set; }
  public DateTime? CompletedDate { get; set; }
  public bool IsCompleted { get; set; }
}
