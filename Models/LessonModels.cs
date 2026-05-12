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
