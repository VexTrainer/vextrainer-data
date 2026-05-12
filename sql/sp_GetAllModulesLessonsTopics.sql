CREATE PROCEDURE [dbo].[sp_GetAllModulesLessonsTopics]
@user_id        INT,
@result_code    INT OUTPUT,
@result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetAllModulesLessonsTopics
  -- Purpose   : Returns the entire active curriculum tree
  --             (modules + lessons + topics) along with the
  --             user's per-lesson progress counts and per-topic
  --             read status in a SINGLE round trip via three
  --             result sets.
  --
  --             Replaces the N+1 pattern of sp_GetAllLessons +
  --             one sp_GetTopicsByLesson per lesson, which floods
  --             SQL Server as the curriculum grows (65 modules x
  --             ~8 lessons = ~520 calls per lessons-page render).
  --
  --             Topic filter mirrors the client's accordion logic:
  --             return H3 and H4 always, plus H2 only when its
  --             lesson has no H3 child (single-page lesson). The
  --             client therefore needs no special filtering — it
  --             can iterate the flat topic list directly.
  --
  --             ORDERING IS A CONTRACT with the client:
  --               - Modules: display_order
  --               - Lessons: module.display_order, lesson.display_order
  --               - Topics : module.display_order, lesson.display_order,
  --                          topic.display_order
  --             The client maps positionally; do not change ORDER BY
  --             without updating the client mapping logic.
  -- ============================================================
  -- Parameters:
  --   @user_id       - ID of the authenticated user (for progress)
  --   @result_code    OUT - 0 = success, 99 = error
  --   @result_message OUT - Human-readable outcome message
  -- ============================================================
  -- Result Sets (in order):
  --
  --   (1) Modules — one row per active module
  --       ModuleId       SMALLINT
  --       ModuleName     VARCHAR
  --       DisplayOrder   TINYINT
  --
  --   (2) Lessons — one row per active lesson (across all modules)
  --       LessonId       SMALLINT
  --       ModuleId       SMALLINT
  --       LessonTitle    VARCHAR
  --       FileName       VARCHAR
  --       DisplayOrder   SMALLINT
  --       IsRead         BIT
  --       TotalTopics    INT  (active topics in this lesson, all heading levels)
  --       TopicsRead     INT  (topics user has read in this lesson)
  --
  --   (3) Topics — one row per navigable active topic
  --       TopicId        INT
  --       LessonId       SMALLINT
  --       TopicTitle     VARCHAR
  --       HeadingLevel   TINYINT  (2 = single-page H2, 3 = H3, 4 = H4)
  --       ParentTopicId  INT      (NULL for H2/H3; parent H3 id for H4)
  --       DisplayOrder   SMALLINT
  --       IsRead         BIT
  -- ============================================================
  -- Result Codes:
  --   0  - Curriculum tree retrieved successfully
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;

  BEGIN TRY
    -- ===== Result Set 1: Modules =====
    SELECT
      module_id     AS ModuleId,
      module_name   AS ModuleName,
      display_order AS DisplayOrder
    FROM t_module
    WHERE is_active = 1
    ORDER BY display_order;

    -- ===== Result Set 2: Lessons with progress =====
    SELECT
      l.lesson_id                                         AS LessonId,
      l.module_id                                         AS ModuleId,
      l.lesson_title                                      AS LessonTitle,
      l.file_name                                         AS FileName,
      l.display_order                                     AS DisplayOrder,
      CASE WHEN ulr.user_id IS NOT NULL THEN 1 ELSE 0 END AS IsRead,
      (SELECT COUNT(*)
       FROM t_topic
       WHERE lesson_id = l.lesson_id
         AND is_active = 1)                               AS TotalTopics,
      (SELECT COUNT(*)
       FROM t_topic t
       INNER JOIN t_user_topic_read utr ON t.topic_id = utr.topic_id
       WHERE t.lesson_id = l.lesson_id
         AND utr.user_id = @user_id)                      AS TopicsRead
    FROM t_lesson l
    INNER JOIN t_module m ON l.module_id  = m.module_id
    LEFT  JOIN t_user_lesson_read ulr ON l.lesson_id = ulr.lesson_id AND ulr.user_id  = @user_id
    WHERE l.is_active = 1
      AND m.is_active = 1
    ORDER BY m.display_order, l.display_order;

    -- ===== Result Set 3: Topics (navigable only) =====
    ;WITH LessonsWithH3 AS (
      SELECT DISTINCT lesson_id
      FROM t_topic
      WHERE heading_level = 3
        AND is_active = 1
    )
    SELECT
      t.topic_id                                          AS TopicId,
      t.lesson_id                                         AS LessonId,
      t.topic_title                                       AS TopicTitle,
      t.heading_level                                     AS HeadingLevel,
      t.parent_topic_id                                   AS ParentTopicId,
      t.display_order                                     AS DisplayOrder,
      CASE WHEN utr.user_id IS NOT NULL THEN 1 ELSE 0 END AS IsRead
    FROM t_topic t
    INNER JOIN t_lesson l         ON l.lesson_id = t.lesson_id
    INNER JOIN t_module m         ON m.module_id = l.module_id
    LEFT  JOIN t_user_topic_read utr ON utr.topic_id = t.topic_id AND utr.user_id  = @user_id
    WHERE t.is_active = 1
      AND l.is_active = 1
      AND m.is_active = 1
      AND (
        t.heading_level IN (3, 4)
        OR (
          t.heading_level = 2
          AND t.lesson_id NOT IN (SELECT lesson_id FROM LessonsWithH3)
        )
      )
    ORDER BY m.display_order, l.display_order, t.display_order;

    SET @result_code    = 0;
    SET @result_message = 'Curriculum tree retrieved successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
