SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetStreakBadgeReport]
  @user_id                 INT,
  @timezone_offset_minutes INT = 0,       -- minutes to add to UTC → local time
                                           -- e.g. -300 = EST, 330 = IST, 0 = UTC
  @result_code             INT OUTPUT,
  @result_message          NVARCHAR(500)  OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetUserActivityReport
  -- Purpose   : Returns the user's reading and quiz activity for
  --             their 7 most recent active days (days on which at
  --             least one topic was read or quiz was attempted),
  --             converted to the caller-supplied local timezone.
  --             Days with no activity are omitted; gaps between
  --             active days are allowed.
  --
  --             Two result sets are returned in a single round
  --             trip, ordered newest-day-first in both cases.
  --             The Android client groups rows by readDate /
  --             attemptDate, then by module → lesson → topic for
  --             topics and flat by quiz for quizzes.
  --
  --             For quizzes attempted more than once on the same
  --             local day, one row is returned per quiz per day
  --             with attemptCount indicating repetitions. The
  --             client appends "(Nx)" to the title when
  --             attemptCount > 1.
  --
  --             Timezone handling: all dates in the database are
  --             UTC. @timezone_offset_minutes is added to each
  --             UTC datetime before deriving a local date.
  --             Offsets outside ±840 minutes (UTC-14 to UTC+14)
  --             are treated as 0 (UTC).
  -- ============================================================
  -- Parameters:
  --   @user_id                  - ID of the authenticated user
  --   @timezone_offset_minutes  - Caller's UTC offset in minutes
  --                               (default 0 = UTC)
  --   @result_code              OUT - 0 = success, 99 = error
  --   @result_message           OUT - Human-readable outcome
  -- ============================================================
  -- Result Sets (in order):
  --
  --   (1) Topics read — one row per topic per active day
  --       readDate      DATE
  --       moduleId      SMALLINT
  --       moduleName    VARCHAR
  --       lessonId      SMALLINT
  --       lessonTitle   VARCHAR
  --       topicId       INT
  --       topicTitle    VARCHAR
  --       Ordered: readDate DESC, module display_order,
  --                lesson display_order, topic display_order
  --
  --   (2) Quiz attempts — one row per quiz per active day
  --       attemptDate   DATE
  --       quizId        SMALLINT
  --       quizTitle     VARCHAR
  --       bestScore     DECIMAL(5,2)  NULL if all incomplete
  --       isCompleted   BIT           1 if any attempt completed
  --       attemptCount  INT           attempts on that day (Nx label)
  --       latestAttemptId INT         for navigation to result
  --       Ordered: attemptDate DESC, quiz_title
  -- ============================================================
  -- Result Codes:
  --   0  - Activity report retrieved successfully
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;

  BEGIN TRY

    -- Clamp offset to valid timezone range (UTC-14 to UTC+14)
    SET @timezone_offset_minutes = CASE
      WHEN @timezone_offset_minutes < -840 THEN 0
      WHEN @timezone_offset_minutes >  840 THEN 0
      ELSE @timezone_offset_minutes
    END;

    -- ===== Find the 7 most recent local days with any activity =====
    -- Combines topic reads and quiz attempts so a day counts even if
    -- the user only did one type of activity.
    DECLARE @active_days TABLE (local_date DATE PRIMARY KEY);

    INSERT INTO @active_days (local_date)
    SELECT TOP 7 local_date
    FROM (
        SELECT DISTINCT
            CAST(DATEADD(MINUTE, @timezone_offset_minutes, utr.read_date) AS DATE) AS local_date
        FROM t_user_topic_read utr
        WHERE utr.user_id   = @user_id
          AND utr.read_date IS NOT NULL

        UNION

        SELECT DISTINCT
            CAST(DATEADD(MINUTE, @timezone_offset_minutes, a.started_date) AS DATE) AS local_date
        FROM t_user_quiz_attempt a
        WHERE a.user_id       = @user_id
          AND a.started_date IS NOT NULL
    ) combined
    ORDER BY local_date DESC;

    -- ===== Result Set 1: Topics =====
    -- One row per topic for each of the 7 active days.
    -- Since PK on t_user_topic_read is (user_id, topic_id), each
    -- topic appears at most once with its most recent read_date,
    -- so no Nx deduplication is needed for topics.
    SELECT
        CAST(DATEADD(MINUTE, @timezone_offset_minutes, utr.read_date) AS DATE) AS readDate,
        m.module_id     AS moduleId,
        m.module_name   AS moduleName,
        l.lesson_id     AS lessonId,
        l.lesson_title  AS lessonTitle,
        t.topic_id      AS topicId,
        t.topic_title   AS topicTitle
    FROM  t_user_topic_read utr
    INNER JOIN t_topic  t ON t.topic_id  = utr.topic_id
    INNER JOIN t_lesson l ON l.lesson_id = t.lesson_id
    INNER JOIN t_module m ON m.module_id = l.module_id
    WHERE utr.user_id = @user_id
      AND t.is_active  = 1
      AND l.is_active  = 1
      AND m.is_active  = 1
      AND CAST(DATEADD(MINUTE, @timezone_offset_minutes, utr.read_date) AS DATE)
              IN (SELECT local_date FROM @active_days)
    ORDER BY
        readDate        DESC,
        m.display_order ASC,
        l.display_order ASC,
        t.display_order ASC;

    -- ===== Result Set 2: Quiz Attempts =====
    -- One row per quiz per active day.
    -- When the same quiz was attempted multiple times on the same
    -- local day, attemptCount > 1 and the client appends "(Nx)".
    -- bestScore is the highest score recorded that day (NULL if
    -- all attempts on that day are incomplete).
    -- latestAttemptId is the most recent attempt for result navigation.
    SELECT
        CAST(DATEADD(MINUTE, @timezone_offset_minutes, a.started_date) AS DATE) AS attemptDate,
        a.quiz_id               AS quizId,
        q.quiz_title            AS quizTitle,
        MAX(a.score)            AS bestScore,
        CAST(MAX(CAST(a.is_completed AS TINYINT)) AS BIT) AS isCompleted,
        COUNT(*)                AS attemptCount,
        MAX(a.attempt_id)       AS latestAttemptId
    FROM  t_user_quiz_attempt a
    INNER JOIN t_quiz q ON q.quiz_id = a.quiz_id
    WHERE a.user_id       = @user_id
      AND a.started_date IS NOT NULL
      AND CAST(DATEADD(MINUTE, @timezone_offset_minutes, a.started_date) AS DATE)
              IN (SELECT local_date FROM @active_days)
    GROUP BY
        CAST(DATEADD(MINUTE, @timezone_offset_minutes, a.started_date) AS DATE),
        a.quiz_id,
        q.quiz_title
    ORDER BY
        attemptDate DESC,
        q.quiz_title ASC;

    SET @result_code    = 0;
    SET @result_message = 'Activity report retrieved successfully';

  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
