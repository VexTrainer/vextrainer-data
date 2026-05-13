CREATE PROCEDURE [dbo].[sp_GetUserWebDashboard]
@user_id        INT,
@result_code    INT OUTPUT,
@result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetUserWebDashboard
  -- Purpose   : Returns everything the VexTrainer Web student
  --             dashboard needs in a SINGLE round trip via six
  --             result sets:
  --
  --               (1) Stats — module/lesson/topic totals and
  --                   completion counts, quiz attempt/avg/best
  --                   score summary, and reading streak.
  --               (2) Continue Learning — one row per lesson the
  --                   user has started but not finished, with the
  --                   next unread navigable topic.
  --               (3) Up Next — at most one row: the first lesson
  --                   in curriculum order the user has not yet
  --                   touched. Client shows this when Continue
  --                   Learning is empty.
  --               (4) Recent Activity — up to 5 most recently
  --                   read topics with timestamps.
  --               (5) Module Progress — one row per active
  --                   module with completed/total lesson counts
  --                   (column names match VexTrainer.Data.Models.
  --                   ModuleProgress: TotalLessons, LessonsRead).
  --               (6) Last Quiz Attempt — at most one row: the
  --                   user's most recent quiz attempt, completed
  --                   or in progress.
  --
  --             Completion semantics: a lesson is "completed"
  --             when explicitly marked read OR when every active
  --             topic in it is read. A module is "completed"
  --             when it has at least one active lesson AND all
  --             active lessons are completed.
  --
  --             "Navigable" topic means H3/H4 always, plus H2
  --             when its lesson has no H3 child (single-page
  --             lesson). Matches the rule used by other web SPs.
  --
  --             Reading streak is computed on UTC dates to match
  --             how read_date is stored.
  --
  --             Note: a separate sp_GetUserDashboard exists for
  --             quiz dashboards. The two procedures are unrelated
  --             and should not be merged.
  -- ============================================================
  -- Parameters:
  --   @user_id       - ID of the authenticated user
  --   @result_code    OUT - 0 = success, 99 = error
  --   @result_message OUT - Human-readable outcome message
  -- ============================================================
  -- Result Sets (in order):
  --
  --   (1) Stats — exactly one row
  --       TotalModules        INT
  --       CompletedModules    INT
  --       TotalLessons        INT
  --       CompletedLessons    INT
  --       TotalTopics         INT
  --       TopicsRead          INT
  --       QuizzesAttempted    INT
  --       QuizzesCompleted    INT
  --       AverageQuizScore    DECIMAL(5,2)  (over completed attempts; 0 if none)
  --       BestQuizScore       DECIMAL(5,2)  (over completed attempts; 0 if none)
  --       ReadingStreak       INT           (consecutive UTC days; 0 if streak broken)
  --
  --   (2) Continue Learning — N rows, ordered by module display_order, lesson display_order
  --       LessonId            SMALLINT
  --       LessonTitle         VARCHAR
  --       ModuleId            SMALLINT
  --       ModuleName          VARCHAR
  --       TopicsRead          INT
  --       TotalTopics         INT
  --       NextTopicId         INT
  --       NextTopicTitle      VARCHAR
  --
  --   (3) Up Next — 0 or 1 row
  --       LessonId            SMALLINT
  --       LessonTitle         VARCHAR
  --       ModuleId            SMALLINT
  --       ModuleName          VARCHAR
  --       FirstTopicId        INT
  --       FirstTopicTitle     VARCHAR
  --
  --   (4) Recent Activity — 0 to 5 rows, most recent first
  --       TopicId             INT
  --       TopicTitle          VARCHAR
  --       LessonId            SMALLINT
  --       LessonTitle         VARCHAR
  --       ModuleId            SMALLINT
  --       ModuleName          VARCHAR
  --       ReadDate            DATETIME2 (UTC)
  --
  --   (5) Module Progress — one row per active module, ordered by display_order
  --       ModuleId            SMALLINT
  --       ModuleName          VARCHAR
  --       TotalLessons        INT
  --       LessonsRead         INT  (completed lessons in this module)
  --
  --   (6) Last Quiz Attempt — 0 or 1 row
  --       AttemptId           INT
  --       QuizId              SMALLINT
  --       QuizTitle           VARCHAR
  --       Score               DECIMAL(5,2)  (NULL if in progress)
  --       StartedDate         DATETIME2
  --       CompletedDate       DATETIME2     (NULL if in progress)
  --       IsCompleted         BIT
  -- ============================================================
  -- Result Codes:
  --   0  - Dashboard data retrieved successfully
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;

  BEGIN TRY
    -- @today aligned to UTC since read_date is stored as UTC datetime2
    DECLARE @today DATE = CAST(GETUTCDATE() AS DATE);

    -- Per-lesson completion status, reused across the stats rollup
    -- and module-progress result set. A lesson is completed if it
    -- is explicitly marked read OR if every active topic in it is read.
    DECLARE @lesson_status TABLE (
      lesson_id    SMALLINT PRIMARY KEY,
      module_id    SMALLINT,
      is_completed BIT
    );

    INSERT @lesson_status (lesson_id, module_id, is_completed)
    SELECT
      l.lesson_id,
      l.module_id,
      CASE
        WHEN ulr.user_id IS NOT NULL THEN CAST(1 AS BIT)
        WHEN tc.total_topics > 0 AND tc.total_topics = tc.topics_read THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
      END
    FROM t_lesson l
    INNER JOIN t_module m         ON l.module_id  = m.module_id
    LEFT  JOIN t_user_lesson_read ulr ON ulr.lesson_id = l.lesson_id AND ulr.user_id  = @user_id
    CROSS APPLY (
      SELECT
        (SELECT COUNT(*)
           FROM t_topic
          WHERE lesson_id = l.lesson_id
            AND is_active = 1)                                AS total_topics,
        (SELECT COUNT(*)
           FROM t_topic t
           INNER JOIN t_user_topic_read utr ON utr.topic_id = t.topic_id
          WHERE t.lesson_id = l.lesson_id
            AND t.is_active = 1
            AND utr.user_id = @user_id)                       AS topics_read
    ) tc
    WHERE l.is_active = 1
      AND m.is_active = 1;

    -- ===== Reading streak (gap-and-island) =====
    -- Distinct UTC read dates, assigned a sequence number; consecutive
    -- dates share the same `date - seq` anchor. Longest run whose last
    -- day is today or yesterday is the active streak.
    DECLARE @reading_streak INT = 0;

    ;WITH ReadDays AS (
      SELECT DISTINCT CAST(read_date AS DATE) AS d
      FROM t_user_topic_read
      WHERE user_id = @user_id
    ),
    Anchored AS (
      SELECT d, DATEADD(DAY, -ROW_NUMBER() OVER (ORDER BY d), d) AS anchor
      FROM ReadDays
    ),
    Groups AS (
      SELECT anchor, COUNT(*) AS streak_len, MAX(d) AS last_d
      FROM Anchored
      GROUP BY anchor
    )
    SELECT @reading_streak = ISNULL(MAX(streak_len), 0)
    FROM Groups
    WHERE last_d >= DATEADD(DAY, -1, @today);

    -- ===== Result Set 1: Stats =====
    DECLARE
      @total_modules     INT, @completed_modules INT,
      @total_lessons     INT, @completed_lessons INT,
      @total_topics      INT, @topics_read       INT,
      @quizzes_attempted INT, @quizzes_completed INT,
      @avg_score DECIMAL(5,2), @best_score DECIMAL(5,2);

    SELECT @total_modules = COUNT(*) FROM t_module WHERE is_active = 1;

    SELECT @completed_modules = COUNT(*)
    FROM t_module m
    WHERE m.is_active = 1
      AND EXISTS (SELECT 1 FROM @lesson_status WHERE module_id = m.module_id)
      AND NOT EXISTS (
        SELECT 1 FROM @lesson_status
        WHERE module_id = m.module_id AND is_completed = 0
      );

    SELECT
      @total_lessons     = COUNT(*),
      @completed_lessons = SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END)
    FROM @lesson_status;

    SELECT @total_topics = COUNT(*)
    FROM t_topic t
    INNER JOIN t_lesson l ON l.lesson_id = t.lesson_id
    INNER JOIN t_module m ON m.module_id = l.module_id
    WHERE t.is_active = 1
      AND l.is_active = 1
      AND m.is_active = 1;

    SELECT @topics_read = COUNT(*)
    FROM t_user_topic_read utr
    INNER JOIN t_topic  t ON t.topic_id  = utr.topic_id
    INNER JOIN t_lesson l ON l.lesson_id = t.lesson_id
    INNER JOIN t_module m ON m.module_id = l.module_id
    WHERE utr.user_id = @user_id
      AND t.is_active = 1
      AND l.is_active = 1
      AND m.is_active = 1;

    SELECT
      @quizzes_attempted = COUNT(DISTINCT quiz_id),
      @quizzes_completed = COUNT(DISTINCT CASE WHEN is_completed = 1 THEN quiz_id END)
    FROM t_user_quiz_attempt
    WHERE user_id = @user_id;

    SELECT
      @avg_score  = AVG(score),
      @best_score = MAX(score)
    FROM t_user_quiz_attempt
    WHERE user_id = @user_id
      AND is_completed = 1;

    SELECT
      ISNULL(@total_modules,     0)                AS TotalModules,
      ISNULL(@completed_modules, 0)                AS CompletedModules,
      ISNULL(@total_lessons,     0)                AS TotalLessons,
      ISNULL(@completed_lessons, 0)                AS CompletedLessons,
      ISNULL(@total_topics,      0)                AS TotalTopics,
      ISNULL(@topics_read,       0)                AS TopicsRead,
      ISNULL(@quizzes_attempted, 0)                AS QuizzesAttempted,
      ISNULL(@quizzes_completed, 0)                AS QuizzesCompleted,
      CAST(ISNULL(@avg_score,  0) AS DECIMAL(5,2)) AS AverageQuizScore,
      CAST(ISNULL(@best_score, 0) AS DECIMAL(5,2)) AS BestQuizScore,
      ISNULL(@reading_streak, 0)                   AS ReadingStreak;

    -- ===== Result Set 2: Continue Learning =====
    ;WITH LessonsWithH3 AS (
      SELECT DISTINCT lesson_id
      FROM t_topic
      WHERE heading_level = 3 AND is_active = 1
    )
    SELECT
      l.lesson_id    AS LessonId,
      l.lesson_title AS LessonTitle,
      l.module_id    AS ModuleId,
      m.module_name  AS ModuleName,
      tc.topics_read AS TopicsRead,
      tc.total_topics AS TotalTopics,
      nxt.topic_id    AS NextTopicId,
      nxt.topic_title AS NextTopicTitle
    FROM t_lesson l
    INNER JOIN t_module m ON l.module_id = m.module_id
    CROSS APPLY (
      SELECT
        (SELECT COUNT(*)
           FROM t_topic
          WHERE lesson_id = l.lesson_id
            AND is_active = 1)                                AS total_topics,
        (SELECT COUNT(*)
           FROM t_topic t
           INNER JOIN t_user_topic_read utr ON utr.topic_id = t.topic_id
          WHERE t.lesson_id = l.lesson_id
            AND t.is_active = 1
            AND utr.user_id = @user_id)                       AS topics_read
    ) tc
    CROSS APPLY (
      SELECT TOP 1 t.topic_id, t.topic_title
      FROM t_topic t
      WHERE t.lesson_id = l.lesson_id
        AND t.is_active = 1
        AND (
          t.heading_level IN (3, 4)
          OR (
            t.heading_level = 2
            AND t.lesson_id NOT IN (SELECT lesson_id FROM LessonsWithH3)
          )
        )
        AND NOT EXISTS (
          SELECT 1 FROM t_user_topic_read utr
          WHERE utr.user_id = @user_id
            AND utr.topic_id = t.topic_id
        )
      ORDER BY t.display_order
    ) nxt
    WHERE l.is_active = 1
      AND m.is_active = 1
      AND tc.topics_read > 0
      AND tc.topics_read < tc.total_topics
    ORDER BY m.display_order, l.display_order;

    -- ===== Result Set 3: Up Next =====
    -- First lesson in curriculum order the user has not started yet
    -- (no topic reads AND no explicit lesson read), with its first
    -- navigable topic. Client shows this when Continue Learning is empty.
    ;WITH LessonsWithH3 AS (
      SELECT DISTINCT lesson_id
      FROM t_topic
      WHERE heading_level = 3 AND is_active = 1
    )
    SELECT TOP 1
      l.lesson_id              AS LessonId,
      l.lesson_title           AS LessonTitle,
      l.module_id              AS ModuleId,
      m.module_name            AS ModuleName,
      first_topic.topic_id     AS FirstTopicId,
      first_topic.topic_title  AS FirstTopicTitle
    FROM t_lesson l
    INNER JOIN t_module m ON l.module_id = m.module_id
    CROSS APPLY (
      SELECT TOP 1 t.topic_id, t.topic_title
      FROM t_topic t
      WHERE t.lesson_id = l.lesson_id
        AND t.is_active = 1
        AND (
          t.heading_level IN (3, 4)
          OR (
            t.heading_level = 2
            AND t.lesson_id NOT IN (SELECT lesson_id FROM LessonsWithH3)
          )
        )
      ORDER BY t.display_order
    ) first_topic
    WHERE l.is_active = 1
      AND m.is_active = 1
      AND NOT EXISTS (
        SELECT 1 FROM t_topic t2
        INNER JOIN t_user_topic_read utr ON utr.topic_id = t2.topic_id
        WHERE t2.lesson_id = l.lesson_id
          AND utr.user_id  = @user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM t_user_lesson_read ulr
        WHERE ulr.lesson_id = l.lesson_id
          AND ulr.user_id   = @user_id
      )
    ORDER BY m.display_order, l.display_order;

    -- ===== Result Set 4: Recent Activity =====
    SELECT TOP 5
      t.topic_id     AS TopicId,
      t.topic_title  AS TopicTitle,
      l.lesson_id    AS LessonId,
      l.lesson_title AS LessonTitle,
      m.module_id    AS ModuleId,
      m.module_name  AS ModuleName,
      utr.read_date  AS ReadDate
    FROM t_user_topic_read utr
    INNER JOIN t_topic  t ON t.topic_id  = utr.topic_id
    INNER JOIN t_lesson l ON l.lesson_id = t.lesson_id
    INNER JOIN t_module m ON m.module_id = l.module_id
    WHERE utr.user_id = @user_id
      AND t.is_active = 1
      AND l.is_active = 1
      AND m.is_active = 1
    ORDER BY utr.read_date DESC;

    -- ===== Result Set 5: Module Progress =====
    -- Column names match VexTrainer.Data.Models.ModuleProgress
    -- (TotalLessons / LessonsRead) so the existing model is reused.
    SELECT
      m.module_id   AS ModuleId,
      m.module_name AS ModuleName,
      ISNULL((SELECT COUNT(*)
              FROM @lesson_status
              WHERE module_id = m.module_id), 0)                AS TotalLessons,
      ISNULL((SELECT SUM(CAST(is_completed AS INT))
              FROM @lesson_status
              WHERE module_id = m.module_id), 0)                AS LessonsRead
    FROM t_module m
    WHERE m.is_active = 1
    ORDER BY m.display_order;

    -- ===== Result Set 6: Last Quiz Attempt =====
    -- Most recent attempt (completed or in progress). Sort by
    -- completed_date if completed, else started_date.
    SELECT TOP 1
      a.attempt_id     AS AttemptId,
      a.quiz_id        AS QuizId,
      q.quiz_title     AS QuizTitle,
      a.score          AS Score,
      a.started_date   AS StartedDate,
      a.completed_date AS CompletedDate,
      a.is_completed   AS IsCompleted
    FROM t_user_quiz_attempt a
    INNER JOIN t_quiz q ON q.quiz_id = a.quiz_id
    WHERE a.user_id = @user_id
    ORDER BY ISNULL(a.completed_date, a.started_date) DESC;

    SET @result_code    = 0;
    SET @result_message = 'Web dashboard data retrieved successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
