namespace VexTrainer.Data.Models;

/// <summary>
/// Container for the two result sets returned by sp_GetStreakBadgeReport.
/// Populated by LessonService.GetStreakBadgeReportAsync and serialised
/// directly to the API response body consumed by the mobile app.
/// </summary>
public class StreakBadgeReport
{
    public List<ActivityTopicItem> Topics  { get; set; } = new();
    public List<ActivityQuizItem>  Quizzes { get; set; } = new();
}

/// <summary>
/// One topic read event — result set 1 of sp_GetStreakBadgeReport.
/// Column names match the aliases in the stored procedure exactly so
/// Dapper can map without configuration.
///
/// The client groups rows by ReadDate, then by ModuleId → LessonId
/// to render the Module => Lesson => Topic hierarchy.
/// Navigation: tapping the row opens TopicViewer for TopicId.
/// </summary>
public class ActivityTopicItem
{
    public DateTime ReadDate    { get; set; }
    public short    ModuleId    { get; set; }
    public string   ModuleName  { get; set; } = string.Empty;
    public short    LessonId    { get; set; }
    public string   LessonTitle { get; set; } = string.Empty;
    public int      TopicId     { get; set; }
    public string   TopicTitle  { get; set; } = string.Empty;
}

/// <summary>
/// One quiz activity record per quiz per active day — result set 2 of
/// sp_GetStreakBadgeReport. When AttemptCount > 1 the client appends
/// "(Nx)" to QuizTitle. BestScore is null when all attempts on that
/// day were incomplete.
///
/// Navigation: tapping the row opens QuizDetail for QuizId so the
/// student can start a new attempt.
/// </summary>
public class ActivityQuizItem
{
    public DateTime AttemptDate      { get; set; }
    public short     QuizId           { get; set; }
    public string    QuizTitle        { get; set; } = string.Empty;
    public decimal?  BestScore        { get; set; }
    public bool      IsCompleted      { get; set; }
    public int       AttemptCount     { get; set; }
    public int       LatestAttemptId  { get; set; }
}
