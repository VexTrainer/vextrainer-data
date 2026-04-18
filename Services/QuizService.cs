using Dapper;
using Microsoft.Data.SqlClient;
using System.Data;
using VexTrainer.Data.Models;
namespace VexTrainer.Data.Services;

/// <summary>
/// QuizService is the database layer for all quiz-related operations in VexTrainer.
/// It uses Dapper to call SQL Server stored procedures and returns standardized
/// ApiResponse objects to the caller.
///
/// A quiz attempt follows a well-defined lifecycle managed across several methods:
///
///   1. GetCategoriesAsync       — browse the category tree to find a quiz
///   2. GetQuizzesByCategoryAsync — list quizzes within a chosen category
///   3. GetQuizDetailsAsync       — inspect a quiz before starting
///   4. StartQuizAttemptAsync     — create an attempt record; receive an attempt ID
///   5. GetQuizQuestionsAsync     — fetch the randomized question set for that attempt
///   6. SubmitAnswerAsync         — submit one answer at a time; receive immediate feedback
///   7. CompleteQuizAsync         — close the attempt and calculate the final score
///   8. GetQuizResultsAsync       — retrieve the full per-question result breakdown
///
/// Additional methods support interrupted sessions and ongoing engagement:
///   - ResumeQuizAttemptAsync    — re-enter an in-progress attempt
///   - GetUserDashboardAsync     — aggregate stats and recent activity
///   - GetUserQuizHistoryAsync   — paginated history of past attempts
///
/// Several methods use QueryMultiple because the stored procedure returns more than one
/// result set in a single round trip. Result sets must always be read in the exact order
/// the stored procedure emits them.
/// </summary>
public class QuizService {
  private readonly string _connectionString;

  public QuizService(string connectionString) {
    _connectionString = connectionString;
  }

  /// <summary>
  /// Returns the full category tree used to browse and filter quizzes.
  ///
  /// The stored procedure returns a flat list of all categories. This method builds
  /// the parent-child hierarchy in memory: categories with no ParentCategoryId become
  /// root nodes, and all others are attached to their parent's Subcategories list via
  /// a dictionary lookup. The response contains only root categories, each already
  /// populated with its nested children — the client does not need to reassemble the
  /// tree itself.
  ///
  /// Note: this method takes no @user_id because categories are global and not
  /// personalized per user.
  ///
  /// Stored procedure : sp_GetCategories
  /// Inputs           : (none)
  /// Outputs          : @result_code, @result_message
  /// Result set       : Flat List&lt;Category&gt; (hierarchy assembled in .NET)
  /// </summary>
  public async Task<ApiResponse<List<Category>>> GetCategoriesAsync() {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var categories = (await connection.QueryAsync<Category>("sp_GetCategories", parameters, commandType: CommandType.StoredProcedure)).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    // Build the parent-child hierarchy in memory from the flat list
    var categoryDict = categories.ToDictionary(c => c.CategoryId);
    var rootCategories = new List<Category>();

    foreach (var category in categories) {
      if (category.ParentCategoryId == null) {
        rootCategories.Add(category);
      }
      else if (categoryDict.ContainsKey(category.ParentCategoryId.Value)) {
        var parent = categoryDict[category.ParentCategoryId.Value];
        parent.Subcategories ??= new List<Category>();
        parent.Subcategories.Add(category);
      }
    }

    return new ApiResponse<List<Category>> {
      Success = resultCode == 0,
      Data = rootCategories,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns all quizzes belonging to a given category, enriched with the user's
  /// attempt history for each quiz (e.g., best score, number of attempts, pass status).
  ///
  /// The @user_id is passed so the stored procedure can join against the user's attempt
  /// table server-side, avoiding a second round trip to hydrate progress data on the client.
  ///
  /// Stored procedure : sp_GetQuizzesByCategory
  /// Inputs           : @category_id, @user_id
  /// Outputs          : @result_code, @result_message
  /// Result set       : List&lt;Quiz&gt;
  /// </summary>
  public async Task<ApiResponse<List<Quiz>>> GetQuizzesByCategoryAsync(short categoryId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@category_id", categoryId);
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var quizzes = (await connection.QueryAsync<Quiz>("sp_GetQuizzesByCategory", parameters, commandType: CommandType.StoredProcedure)).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<List<Quiz>> {
      Success = resultCode == 0,
      Data = quizzes,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns the metadata and user-specific context for a single quiz, intended for
  /// a "quiz detail / start" screen before the user commits to an attempt.
  ///
  /// The returned QuizDetails typically includes question count, passing threshold,
  /// estimated duration, and the user's previous best score so they can make an
  /// informed decision before starting. Returns null in Data if the quiz ID is not
  /// found; callers should check Success before rendering.
  ///
  /// Stored procedure : sp_GetQuizDetails
  /// Inputs           : @quiz_id, @user_id
  /// Outputs          : @result_code, @result_message
  /// Result set       : Single QuizDetails row (or empty)
  /// </summary>
  public async Task<ApiResponse<QuizDetails>> GetQuizDetailsAsync(short quizId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@quiz_id", quizId);
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var quizDetails = await connection.QueryFirstOrDefaultAsync<QuizDetails>("sp_GetQuizDetails", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<QuizDetails> {
      Success = resultCode == 0,
      Data = quizDetails,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Creates a new attempt record in the database and returns the attempt ID and
  /// total question count needed to drive the quiz session.
  ///
  /// This must be called before GetQuizQuestionsAsync — the attempt ID returned here
  /// is the key that ties all subsequent answer submissions and the final completion
  /// call back to this specific session. The stored procedure may enforce business rules
  /// such as attempt limits per quiz, returning a non-zero result_code if the user is
  /// not permitted to start another attempt.
  ///
  /// Stored procedure : sp_StartQuizAttempt
  /// Inputs           : @user_id, @quiz_id
  /// Outputs          : @attempt_id, @total_questions, @result_code, @result_message
  /// </summary>
  public async Task<ApiResponse<StartQuizResponse>> StartQuizAttemptAsync(short quizId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@user_id", userId);
    parameters.Add("@quiz_id", quizId);
    parameters.Add("@attempt_id", dbType: DbType.Int32, direction: ParameterDirection.Output);   // t_user_quiz_attempt.attempt_id is int, not smallint
    parameters.Add("@total_questions", dbType: DbType.Byte, direction: ParameterDirection.Output);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("sp_StartQuizAttempt", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (resultCode != 0) {
      return new ApiResponse<StartQuizResponse> {
        Success = false,
        Message = resultMessage,
        ResultCode = resultCode
      };
    }

    return new ApiResponse<StartQuizResponse> {
      Success = true,
      Data = new StartQuizResponse {
        AttemptId = parameters.Get<int>("@attempt_id"),
        QuizId = quizId,
        StartedDate = DateTime.UtcNow,
        TotalQuestions = parameters.Get<byte>("@total_questions")
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Fetches the randomized question set and their answer options for an active attempt.
  ///
  /// The stored procedure returns two result sets — questions and answers — in a single
  /// round trip. Answers are returned as a flat list (not pre-grouped) and assembled onto
  /// their parent questions in memory by grouping on QuestionId. This avoids shipping a
  /// denormalized result set with repeated question data for every answer row.
  ///
  /// IMPORTANT: Result sets must be read in order — questions first, answers second —
  /// matching the sequence the stored procedure emits them.
  ///
  /// The @user_id is included so the procedure can verify the attempt belongs to that
  /// user before returning any content.
  ///
  /// Stored procedure : sp_GetQuizQuestions
  /// Inputs           : @attempt_id, @user_id
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) List&lt;Question&gt;
  ///                    (2) List&lt;Answer&gt;  (assembled onto questions in memory)
  /// </summary>
  public async Task<ApiResponse<QuizQuestionsResponse>> GetQuizQuestionsAsync(int attemptId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@attempt_id", attemptId);
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_GetQuizQuestions", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the order the stored procedure emits them
    var questions = (await multi.ReadAsync<Question>()).ToList();
    var answers = (await multi.ReadAsync<Answer>()).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    // Group the flat answer list onto their parent questions in memory
    var answersByQuestion = answers.GroupBy(a => a.QuestionId)
        .ToDictionary(g => g.Key, g => g.ToList());

    foreach (var question in questions) {
      question.Answers = answersByQuestion.TryGetValue(question.QuestionId, out var qAnswers) ? qAnswers : new List<Answer>();
    }

    return new ApiResponse<QuizQuestionsResponse> {
      Success = resultCode == 0,
      Data = new QuizQuestionsResponse {
        AttemptId = attemptId,
        Questions = questions
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Records a single answer submission and returns immediate feedback to the user.
  ///
  /// The answer is passed as a JSON string (@user_answer_json) to support flexible
  /// question types — single-choice, multi-choice, ordering, and so on — without
  /// requiring a different stored procedure per type. The database evaluates correctness
  /// and returns the explanation, the correct answer (also as JSON for the client to
  /// render), the running score, and the count of questions answered so far.
  ///
  /// This enables real-time feedback after each question rather than withholding all
  /// results until the quiz is completed.
  ///
  /// Stored procedure : sp_SubmitAnswer
  /// Inputs           : @attempt_id, @question_id, @user_answer_json, @user_id
  /// Outputs          : @is_correct, @explanation, @correct_answer_json,
  ///                    @current_score, @questions_answered, @result_code, @result_message
  /// </summary>
  public async Task<ApiResponse<SubmitAnswerResponse>> SubmitAnswerAsync(int attemptId, SubmitAnswerRequest request, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@attempt_id", attemptId);
    parameters.Add("@question_id", request.QuestionId);
    parameters.Add("@user_answer_json", request.AnswerJson, DbType.String, size: -1);   // nvarchar(max) in SP
    parameters.Add("@user_id", userId);
    parameters.Add("@is_correct", dbType: DbType.Boolean, direction: ParameterDirection.Output);
    parameters.Add("@explanation", dbType: DbType.String, size: -1, direction: ParameterDirection.Output);
    parameters.Add("@correct_answer_json", dbType: DbType.String, size: -1, direction: ParameterDirection.Output);
    parameters.Add("@current_score", dbType: DbType.Decimal, direction: ParameterDirection.Output);
    parameters.Add("@questions_answered", dbType: DbType.Byte, direction: ParameterDirection.Output);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("sp_SubmitAnswer", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (resultCode != 0) {
      return new ApiResponse<SubmitAnswerResponse> {
        Success = false,
        Message = resultMessage,
        ResultCode = resultCode
      };
    }

    return new ApiResponse<SubmitAnswerResponse> {
      Success = true,
      Data = new SubmitAnswerResponse {
        IsCorrect = parameters.Get<bool>("@is_correct"),
        Explanation = parameters.Get<string>("@explanation"),
        CorrectAnswerJson = parameters.Get<string>("@correct_answer_json"),
        CurrentScore = parameters.Get<decimal>("@current_score"),
        QuestionsAnswered = parameters.Get<byte>("@questions_answered")
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Closes an in-progress attempt and calculates the final score.
  ///
  /// sp_CompleteQuiz tallies all submitted answers, computes the percentage score,
  /// evaluates it against the quiz's passing threshold, and marks the attempt as
  /// complete so it cannot receive further answer submissions. The final score,
  /// correct answer count, total question count, and pass/fail flag are all returned
  /// as OUTPUT parameters rather than a result set because only a single row is ever
  /// produced — avoiding the overhead of a result set for scalar values.
  ///
  /// After this call succeeds, GetQuizResultsAsync can be used to retrieve the full
  /// per-question breakdown for a review screen.
  ///
  /// Stored procedure : sp_CompleteQuiz
  /// Inputs           : @attempt_id, @user_id
  /// Outputs          : @score, @correct_answers, @total_questions, @passed,
  ///                    @result_code, @result_message
  /// </summary>
  public async Task<ApiResponse<CompleteQuizResponse>> CompleteQuizAsync(int attemptId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@attempt_id", attemptId);
    parameters.Add("@user_id", userId);
    parameters.Add("@score", dbType: DbType.Decimal, direction: ParameterDirection.Output);   // matches t_user_quiz_attempt.score column
    parameters.Add("@correct_answers", dbType: DbType.Byte, direction: ParameterDirection.Output);
    parameters.Add("@total_questions", dbType: DbType.Byte, direction: ParameterDirection.Output);
    parameters.Add("@passed", dbType: DbType.Boolean, direction: ParameterDirection.Output);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    await connection.ExecuteAsync("sp_CompleteQuiz", parameters, commandType: CommandType.StoredProcedure);

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (resultCode != 0) {
      return new ApiResponse<CompleteQuizResponse> {
        Success = false,
        Message = resultMessage,
        ResultCode = resultCode
      };
    }

    return new ApiResponse<CompleteQuizResponse> {
      Success = true,
      Data = new CompleteQuizResponse {
        AttemptId = attemptId,
        FinalScore = parameters.Get<decimal>("@score"),
        CorrectAnswers = parameters.Get<byte>("@correct_answers"),
        TotalQuestions = parameters.Get<byte>("@total_questions"),
        Passed = parameters.Get<bool>("@passed"),
        CompletedDate = DateTime.UtcNow
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns the full result breakdown for a completed attempt, intended for the
  /// post-quiz review screen.
  ///
  /// The stored procedure returns two result sets in a single round trip:
  ///   1. A summary row (overall score, pass/fail, time taken) → QuizResultSummary
  ///   2. A per-question list showing what the user answered, whether it was correct,
  ///      and the explanation → List&lt;QuestionResult&gt;
  ///
  /// If the summary row is missing (e.g., the attempt ID is invalid), an empty
  /// QuizResultSummary is substituted so the caller always receives a valid object.
  ///
  /// Stored procedure : sp_GetQuizResults
  /// Inputs           : @attempt_id, @user_id
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) QuizResultSummary row
  ///                    (2) List&lt;QuestionResult&gt;
  /// </summary>
  public async Task<ApiResponse<QuizResults>> GetQuizResultsAsync(int attemptId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@attempt_id", attemptId);
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_GetQuizResults", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the order the stored procedure emits them
    var summary = await multi.ReadFirstOrDefaultAsync<QuizResultSummary>();
    var questions = (await multi.ReadAsync<QuestionResult>()).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<QuizResults> {
      Success = resultCode == 0,
      Data = new QuizResults {
        Summary = summary ?? new QuizResultSummary(),   // never null — caller can always bind
        Questions = questions
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Re-enters an attempt that was started but not completed, restoring enough state
  /// for the client to pick up exactly where the user left off.
  ///
  /// The stored procedure returns two result sets:
  ///   1. The attempt's metadata (quiz ID, question count, time elapsed, etc.)
  ///      → ResumeQuizData
  ///   2. A list of question IDs the user has already answered → List&lt;int&gt;
  ///
  /// The answered question IDs are attached to the ResumeQuizData object before
  /// returning so the client can skip already-answered questions and display an
  /// accurate "X of N answered" progress indicator without re-fetching the full
  /// question set.
  ///
  /// Stored procedure : sp_ResumeQuizAttempt
  /// Inputs           : @attempt_id, @user_id
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) ResumeQuizData row
  ///                    (2) List&lt;int&gt; of already-answered question IDs
  /// </summary>
  public async Task<ApiResponse<ResumeQuizData>> ResumeQuizAttemptAsync(int attemptId, int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@attempt_id", attemptId);
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_ResumeQuizAttempt", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the order the stored procedure emits them
    var attemptData = await multi.ReadFirstOrDefaultAsync<ResumeQuizData>();
    var answeredQuestions = (await multi.ReadAsync<int>()).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (attemptData != null) {
      attemptData.AnsweredQuestionIds = answeredQuestions;
    }

    return new ApiResponse<ResumeQuizData> {
      Success = resultCode == 0,
      Data = attemptData,
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns the aggregate statistics and recent activity shown on the user's
  /// home dashboard.
  ///
  /// The stored procedure returns two result sets in a single round trip:
  ///   1. A stats summary row (total quizzes taken, overall pass rate, average score,
  ///      etc.) → UserDashboard
  ///   2. A list of the user's most recent quiz attempts → List&lt;RecentAttempt&gt;
  ///
  /// The recent attempts are attached to the UserDashboard object before returning.
  /// If no stats row exists (brand-new user with no activity), an empty UserDashboard
  /// is returned rather than null so the client always has a valid object to bind against.
  ///
  /// Stored procedure : sp_GetUserDashboard
  /// Inputs           : @user_id
  /// Outputs          : @result_code, @result_message
  /// Result sets      : (1) UserDashboard stats row
  ///                    (2) List&lt;RecentAttempt&gt;
  /// </summary>
  public async Task<ApiResponse<UserDashboard>> GetUserDashboardAsync(int userId) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@user_id", userId);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    using var multi = await connection.QueryMultipleAsync("sp_GetUserDashboard", parameters, commandType: CommandType.StoredProcedure);

    // Read result sets in the order the stored procedure emits them
    var stats = await multi.ReadFirstOrDefaultAsync<UserDashboard>();
    var recentAttempts = (await multi.ReadAsync<RecentAttempt>()).ToList();

    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    if (stats != null) {
      stats.RecentAttempts = recentAttempts;
    }

    return new ApiResponse<UserDashboard> {
      Success = resultCode == 0,
      Data = stats ?? new UserDashboard(),   // never null — caller can always bind
      Message = resultMessage,
      ResultCode = resultCode
    };
  }

  /// <summary>
  /// Returns a paginated list of all quiz attempts the user has ever made.
  ///
  /// Pagination is handled entirely server-side: the caller supplies a 1-based page
  /// number and page size, and the stored procedure returns only that slice of records.
  /// The total record count is returned as an OUTPUT parameter (not a second result set)
  /// so the client can calculate the total number of pages without a separate COUNT query.
  ///
  /// Default values (page = 1, pageSize = 20) mean the caller can omit these parameters
  /// to get the first page with standard sizing.
  ///
  /// Stored procedure : sp_GetUserQuizHistory
  /// Inputs           : @user_id, @page, @page_size
  /// Outputs          : @total_count, @result_code, @result_message
  /// Result set       : List&lt;QuizHistoryItem&gt; (one page of results)
  /// </summary>
  public async Task<ApiResponse<QuizHistoryResponse>> GetUserQuizHistoryAsync(int userId, int page = 1, int pageSize = 20) {
    using var connection = new SqlConnection(_connectionString);
    var parameters = new DynamicParameters();
    parameters.Add("@user_id", userId);
    parameters.Add("@page", page);
    parameters.Add("@page_size", pageSize);
    parameters.Add("@total_count", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_code", dbType: DbType.Int32, direction: ParameterDirection.Output);
    parameters.Add("@result_message", dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

    var attempts = (await connection.QueryAsync<QuizHistoryItem>("sp_GetUserQuizHistory", parameters, commandType: CommandType.StoredProcedure)).ToList();

    var totalCount = parameters.Get<int>("@total_count");
    var resultCode = parameters.Get<int>("@result_code");
    var resultMessage = parameters.Get<string>("@result_message");

    return new ApiResponse<QuizHistoryResponse> {
      Success = resultCode == 0,
      Data = new QuizHistoryResponse {
        Attempts = attempts,
        TotalCount = totalCount,
        Page = page,
        PageSize = pageSize
      },
      Message = resultMessage,
      ResultCode = resultCode
    };
  }
}