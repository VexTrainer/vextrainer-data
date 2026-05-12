using Dapper;
using Microsoft.Data.SqlClient;
using System.Data;
using VexTrainer.Data.Models;
namespace VexTrainer.Data.Services;

/// <summary>
/// LessonService is the database layer for all curriculum-browsing and reading-progress
/// operations in VexTrainer. It uses Dapper to call SQL Server stored procedures and returns
/// standardized ApiResponse objects to the caller.
///
/// The curriculum hierarchy is: Module → Lesson → Topic.
///   - A Module is a top-level grouping (e.g., "Autonomous Programming").
///   - A Lesson belongs to one Module and groups related content.
///   - A Topic is the finest-grained unit of content inside a Lesson.
///
/// Almost every read method accepts a @user_id so the stored procedure can join against the
/// user's progress tables and return per-item read/completion flags alongside the content —
/// avoiding a separate round trip to hydrate progress data on the client.
///
/// General pattern used throughout this class:
///   1. Build a DynamicParameters object with input values and typed OUTPUT placeholders.
///   2. Call a stored procedure via Dapper's QueryAsync / QueryFirstOrDefaultAsync /
///      QueryMultipleAsync / ExecuteAsync depending on the expected shape of the result.
///   3. Read the OUTPUT parameters (@result_code, @result_message).
///   4. Return an ApiResponse whose Success flag is driven by result_code == 0.
/// </summary>
public class LessonService
{
    private readonly string _connectionString;

    public LessonService(string connectionString)
    {
        _connectionString = connectionString;
    }

    /// <summary>
    /// Returns all curriculum modules visible to the given user.
    ///
    /// The stored procedure joins the module list with the user's progress data so each
    /// returned Module object already carries completion or read-state information — the
    /// client does not need a second call to determine which modules the user has started
    /// or finished.
    ///
    /// Stored procedure : sp_GetModules
    /// Inputs           : @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : List&lt;Module&gt;
    /// </summary>
    public async Task<ApiResponse<List<Module>>> GetModulesAsync(int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var modules = (await connection.QueryAsync<Module>("sp_GetModules", parameters, commandType: CommandType.StoredProcedure)).ToList();

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<List<Module>>
        {
            Success = resultCode == 0,
            Data = modules,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns all lessons that belong to a given module, enriched with the user's
    /// per-lesson read/completion status.
    ///
    /// The result is used by the client to render the lesson list for a module screen,
    /// including visual indicators showing which lessons have already been read.
    ///
    /// Stored procedure : sp_GetLessonsByModule
    /// Inputs           : @module_id, @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : List&lt;Lesson&gt;
    /// </summary>
    public async Task<ApiResponse<List<Lesson>>> GetLessonsByModuleAsync(short moduleId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@module_id", moduleId);
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var lessons = (await connection.QueryAsync<Lesson>("sp_GetLessonsByModule", parameters, commandType: CommandType.StoredProcedure)).ToList();

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<List<Lesson>>
        {
            Success = resultCode == 0,
            Data = lessons,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns the full detail record for a single lesson, including metadata and the
    /// user's read status for that lesson.
    ///
    /// Returns a single LessonDetails object (or null if the lesson ID is not found).
    /// Callers should check Success and whether Data is null before rendering.
    ///
    /// Stored procedure : sp_GetLessonDetails
    /// Inputs           : @lesson_id, @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : Single LessonDetails row (or empty)
    /// </summary>
    public async Task<ApiResponse<LessonDetails>> GetLessonDetailsAsync(short lessonId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@lesson_id", lessonId);
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var lessonDetails = await connection.QueryFirstOrDefaultAsync<LessonDetails>("sp_GetLessonDetails", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<LessonDetails>
        {
            Success = resultCode == 0,
            Data = lessonDetails,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns all topics within a lesson, ordered by display_order so the client can
    /// map them directly to the screen without additional sorting.
    ///
    /// IMPORTANT: The stored procedure guarantees ordering by display_order. Client code
    /// must not re-sort this list or the intended reading sequence will break.
    ///
    /// Each topic includes the user's read status so the client can show progress
    /// indicators at the topic level.
    ///
    /// Stored procedure : sp_GetTopicsByLesson
    /// Inputs           : @lesson_id, @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : List&lt;Topic&gt; ordered by display_order
    /// </summary>
    public async Task<ApiResponse<List<Topic>>> GetTopicsByLessonAsync(short lessonId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@lesson_id", lessonId);
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var topics = (await connection.QueryAsync<Topic>("sp_GetTopicsByLesson", parameters, commandType: CommandType.StoredProcedure)).ToList();

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<List<Topic>>
        {
            Success = resultCode == 0,
            Data = topics,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Records that a user has read a lesson.
    ///
    /// Calls sp_MarkLessonRead, which upserts a row in the user's lesson-progress table
    /// (insert on first read, no-op or timestamp update on repeat). This is the signal
    /// the system uses to drive completion percentages and dashboard progress indicators.
    ///
    /// Stored procedure : sp_MarkLessonRead
    /// Inputs           : @user_id, @lesson_id
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> MarkLessonReadAsync(short lessonId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@lesson_id", lessonId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_MarkLessonRead", parameters, commandType: CommandType.StoredProcedure);

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
    /// Records that a user has read a specific topic within a lesson.
    ///
    /// Mirrors MarkLessonReadAsync at the finer Topic level. sp_MarkTopicRead upserts a
    /// row in the user's topic-progress table. The client typically calls this when the
    /// user navigates away from or scrolls past a topic, treating it as "seen."
    ///
    /// Stored procedure : sp_MarkTopicRead
    /// Inputs           : @user_id, @topic_id
    /// Outputs          : @result_code, @result_message
    /// </summary>
    public async Task<ApiResponse<object>> MarkTopicReadAsync(int topicId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@topic_id", topicId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await connection.ExecuteAsync("sp_MarkTopicRead", parameters, commandType: CommandType.StoredProcedure);

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
    /// Returns a comprehensive reading-progress dashboard for the user.
    ///
    /// This is the only method in this service that uses QueryMultiple, because the stored
    /// procedure returns three result sets in a single round trip:
    ///   1. Overall stats   → hydrated into a ReadingProgress object (totals, percentages)
    ///   2. Recent lessons  → List&lt;RecentLesson&gt; attached to stats.RecentLessons
    ///   3. Module progress → List&lt;ModuleProgress&gt; attached to stats.ModuleProgress
    ///
    /// The three sets are read in order and assembled into a single ReadingProgress object
    /// before returning. If the stats row is missing (e.g., brand-new user with no activity),
    /// an empty ReadingProgress is returned rather than null, so the client always gets a
    /// valid object to bind against.
    ///
    /// Stored procedure : sp_GetUserReadingProgress
    /// Inputs           : @user_id
    /// Outputs          : @result_code, @result_message
    /// Result sets      : (1) ReadingProgress stats row
    ///                    (2) List&lt;RecentLesson&gt;
    ///                    (3) List&lt;ModuleProgress&gt;
    /// </summary>
    public async Task<ApiResponse<ReadingProgress>> GetReadingProgressAsync(int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        using var multi = await connection.QueryMultipleAsync("sp_GetUserReadingProgress", parameters, commandType: CommandType.StoredProcedure);

        // Read the three result sets in the order the stored procedure emits them
        var stats = await multi.ReadFirstOrDefaultAsync<ReadingProgress>();
        var recentLessons = (await multi.ReadAsync<RecentLesson>()).ToList();
        var moduleProgress = (await multi.ReadAsync<ModuleProgress>()).ToList();

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        if (stats != null)
        {
            stats.RecentLessons = recentLessons;
            stats.ModuleProgress = moduleProgress;
        }

        return new ApiResponse<ReadingProgress>
        {
            Success = resultCode == 0,
            Data = stats ?? new ReadingProgress(),   // never null — caller can always bind
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns every lesson in the curriculum, each decorated with the user's read/
    /// completion status.
    ///
    /// Intended for views that need a flat, cross-module list — such as a search results
    /// screen or an admin overview — rather than the hierarchical Module → Lesson drill-down
    /// provided by GetModulesAsync / GetLessonsByModuleAsync.
    ///
    /// Stored procedure : sp_GetAllLessons
    /// Inputs           : @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : List&lt;LessonWithProgress&gt;
    /// </summary>
    public async Task<ApiResponse<List<LessonWithProgress>>> GetAllLessonsAsync(int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var lessons = (await connection.QueryAsync<LessonWithProgress>("sp_GetAllLessons", parameters, commandType: CommandType.StoredProcedure)).ToList();

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<List<LessonWithProgress>>
        {
            Success = resultCode == 0,
            Data = lessons,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns the full content and navigation context for a single topic.
    ///
    /// In addition to the topic's own content, sp_GetTopicDetails includes prev/next topic
    /// IDs so the client can render forward/back navigation without fetching the full topic
    /// list, and a breadcrumb trail (Module → Lesson → Topic) so the user always knows
    /// where they are in the curriculum hierarchy.
    ///
    /// Returns null in Data if the topic ID does not exist; callers should check Success
    /// before attempting to render.
    ///
    /// Stored procedure : sp_GetTopicDetails
    /// Inputs           : @topic_id, @user_id
    /// Outputs          : @result_code, @result_message
    /// Result set       : Single TopicDetails row (or empty)
    /// </summary>
    public async Task<ApiResponse<TopicDetails>> GetTopicDetailsAsync(int topicId, int userId)
    {
        using var connection = new SqlConnection(_connectionString);
        var parameters = new DynamicParameters();
        parameters.Add("@topic_id", topicId);
        parameters.Add("@user_id", userId);
        parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        var topicDetails = await connection.QueryFirstOrDefaultAsync<TopicDetails>("sp_GetTopicDetails", parameters, commandType: CommandType.StoredProcedure);

        var resultCode = parameters.Get<int>("@result_code");
        var resultMessage = parameters.Get<string>("@result_message");

        return new ApiResponse<TopicDetails>
        {
            Success = resultCode == 0,
            Data = topicDetails,
            Message = resultMessage,
            ResultCode = resultCode
        };
    }

    /// <summary>
    /// Returns the entire active curriculum tree (modules + lessons + topics) plus
    /// the user's per-lesson progress counts and per-topic read status in a SINGLE
    /// round trip. Replaces the older N+1 pattern of GetAllLessonsAsync followed by
    /// one GetTopicsByLessonAsync per lesson, which floods SQL Server as the
    /// curriculum grows.
    ///
    /// The stored procedure returns three result sets, read here in order:
    ///   1. Modules — List&lt;ModuleNode&gt;
    ///   2. Lessons — List&lt;LessonNode&gt; (with progress, FK ModuleId)
    ///   3. Topics  — List&lt;TopicNode&gt;  (navigable only, FK LessonId)
    /// The caller groups topics by LessonId and lessons by ModuleId in memory to
    /// rebuild the Module → Lesson → Topic hierarchy used by the lessons page.
    ///
    /// Stored procedure : sp_GetAllModulesLessonsTopics
    /// Inputs           : @user_id
    /// Outputs          : @result_code, @result_message
    /// Result sets      : (1) List&lt;ModuleNode&gt;
    ///                    (2) List&lt;LessonNode&gt;
    ///                    (3) List&lt;TopicNode&gt;
    /// </summary>
    public async Task<ApiResponse<ModulesLessonsTopicsTree>> GetAllModulesLessonsTopicsAsync(int userId) {
      using var connection = new SqlConnection(_connectionString);
      var parameters = new DynamicParameters();
      parameters.Add("@user_id", userId);
      parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
      parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);
    
      using var multi = await connection.QueryMultipleAsync(
          "sp_GetAllModulesLessonsTopics", parameters, commandType: CommandType.StoredProcedure);
    
      // Read the three result sets in the order the stored procedure emits them
      var modules = (await multi.ReadAsync<ModuleNode>()).ToList();
      var lessons = (await multi.ReadAsync<LessonNode>()).ToList();
      var topics = (await multi.ReadAsync<TopicNode>()).ToList();
    
      var resultCode = parameters.Get<int>("@result_code");
      var resultMessage = parameters.Get<string>("@result_message");
    
      return new ApiResponse<ModulesLessonsTopicsTree> {
        Success = resultCode == 0,
        Data = new ModulesLessonsTopicsTree {
          Modules = modules,
          Lessons = lessons,
          Topics = topics
        },
        Message = resultMessage,
        ResultCode = resultCode
      };
    }
}