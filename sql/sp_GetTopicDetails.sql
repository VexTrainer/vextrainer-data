SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetTopicDetails]
@topic_id       INT,
@user_id        INT,
@result_code    INT OUTPUT,
@result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetTopicDetails
  -- Purpose   : Returns full details for a single topic including
  --             cross-module/cross-lesson prev/next navigation
  --             and breadcrumb data.
  --
  --             Navigation is computed against a flat sequence of
  --             "navigable" topics spanning the entire curriculum
  --             (modules ordered by display_order, lessons within
  --             a module ordered by display_order, topics within a
  --             lesson ordered by display_order). This lets the
  --             user navigate continuously from the last topic of
  --             one lesson to the first of the next, and across
  --             module boundaries.
  --
  --             A topic is "navigable" if:
  --               - heading_level is 3 or 4, OR
  --               - heading_level is 2 AND the lesson has no H3
  --                 children (single-page lesson — the H2 is the
  --                 only content topic). This mirrors the accordion
  --                 fallback in the client.
  --
  --             FileName is a zero-padded composite key:
  --               MMMMM-LLLLL-TTTTT  (module / lesson / topic)
  --             Previous/Next FileName values may point to a
  --             different lesson and/or module than the current
  --             topic — the client parses the IDs out of the
  --             filename to build the link.
  --
  --             Returns result code -1 (not 1) for not-found to
  --             distinguish a missing topic from a business-rule
  --             rejection in the calling layer.
  -- ============================================================
  -- Parameters:
  --   @topic_id      - ID of the topic to retrieve
  --   @user_id       - ID of the authenticated user (for IsRead)
  --   @result_code    OUT - 0 = success, -1 = topic not found,
  --                         99 = error
  --   @result_message OUT - Human-readable outcome message
  -- ============================================================
  -- Result Set (1 row on success):
  --   TopicId              INT
  --   TopicTitle           VARCHAR
  --   HeadingLevel         TINYINT
  --   FileName             VARCHAR   (MMMMM-LLLLL-TTTTT)
  --   IsRead               BIT
  --   PreviousTopicId      INT       (NULL if none)
  --   PreviousTopicTitle   VARCHAR   (NULL if none)
  --   PreviousFileName     VARCHAR   (NULL if none; may be a different module/lesson)
  --   NextTopicId          INT       (NULL if none)
  --   NextTopicTitle       VARCHAR   (NULL if none)
  --   NextFileName         VARCHAR   (NULL if none; may be a different module/lesson)
  --   ModuleId             SMALLINT
  --   ModuleName           VARCHAR
  --   LessonId             SMALLINT
  --   LessonTitle          VARCHAR
  --   ParentTopicTitle     VARCHAR   (NULL for H3; parent H3 title for H4)
  --   IsBookmarked         BIT
  -- ============================================================
  -- Result Codes:
  --   0  - Topic details retrieved successfully
  --  -1  - No topic found with the supplied topic_id
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;
  BEGIN TRY
    DECLARE @lesson_id SMALLINT,
            @module_id SMALLINT,
			@is_bookmarked bit = 0

    -- Resolve lesson for the requested topic
    SELECT @lesson_id = lesson_id
    FROM t_topic
    WHERE topic_id = @topic_id;

    IF @lesson_id IS NULL
    BEGIN
      SET @result_code    = -1;
      SET @result_message = 'Topic not found';
      RETURN;
    END

    -- Resolve module from lesson
    SELECT @module_id = module_id
    FROM t_lesson
    WHERE lesson_id = @lesson_id;

    IF EXISTS (SELECT 1
	             FROM t_bookmark b
	             WHERE b.user_id = @user_id
	               AND b.topic_id = @topic_id)
	  SET @is_bookmarked = CAST(1 AS BIT)

    -- Build a flat global sequence of navigable topics, then find
    -- prev/next relative to the current topic's seq.
    ;WITH LessonsWithH3 AS (
      SELECT DISTINCT lesson_id
      FROM t_topic
      WHERE heading_level = 3
        AND is_active = 1
    ),
    NavigableTopics AS (
      SELECT
        t.topic_id,
        t.topic_title,
        t.lesson_id,
        l.module_id,
        ROW_NUMBER() OVER (
          ORDER BY m.display_order, l.display_order, t.display_order
        ) AS seq
      FROM t_topic t
      INNER JOIN t_lesson l ON l.lesson_id = t.lesson_id
      INNER JOIN t_module m ON m.module_id = l.module_id
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
    ),
    CurrentSeq AS (
      SELECT seq FROM NavigableTopics WHERE topic_id = @topic_id
    )
    SELECT
      -- Current topic
      t.topic_id                                          AS TopicId,
      t.topic_title                                       AS TopicTitle,
      t.heading_level                                     AS HeadingLevel,
      CONCAT(FORMAT(@module_id, '00000'), '-', FORMAT(@lesson_id, '00000'), '-', FORMAT(t.topic_id, '00000')) AS FileName,
      CASE WHEN rt.topic_id IS NOT NULL
           THEN CAST(1 AS BIT)
           ELSE CAST(0 AS BIT) END                        AS IsRead,
      -- Previous (last navigable before current in global sequence)
      prev.topic_id                                       AS PreviousTopicId,
      prev.topic_title                                    AS PreviousTopicTitle,
      CASE WHEN prev.topic_id IS NULL THEN NULL
           ELSE CONCAT(FORMAT(prev.module_id, '00000'), '-', FORMAT(prev.lesson_id, '00000'), '-', FORMAT(prev.topic_id, '00000'))
      END                                                 AS PreviousFileName,
      -- Next (first navigable after current in global sequence)
      nxt.topic_id                                        AS NextTopicId,
      nxt.topic_title                                     AS NextTopicTitle,
      CASE WHEN nxt.topic_id IS NULL THEN NULL
           ELSE CONCAT(FORMAT(nxt.module_id, '00000'), '-', FORMAT(nxt.lesson_id, '00000'), '-', FORMAT(nxt.topic_id, '00000'))
      END                                                 AS NextFileName,
      -- Breadcrumb
      @module_id                                          AS ModuleId,
      m.module_name                                       AS ModuleName,
      @lesson_id                                          AS LessonId,
      l.lesson_title                                      AS LessonTitle,
      parent.topic_title                                  AS ParentTopicTitle,
	  @is_bookmarked                                      AS IsBookmarked
    FROM t_topic t
      INNER JOIN t_lesson l         ON l.lesson_id     = t.lesson_id
      INNER JOIN t_module m         ON m.module_id     = l.module_id
      LEFT JOIN t_user_topic_read rt ON rt.topic_id   = t.topic_id AND rt.user_id    = @user_id
      LEFT JOIN t_topic parent     ON parent.topic_id = t.parent_topic_id
    OUTER APPLY (
      SELECT TOP 1 nt.topic_id, nt.topic_title, nt.lesson_id, nt.module_id
      FROM NavigableTopics nt
      WHERE nt.seq < (SELECT seq FROM CurrentSeq)
      ORDER BY nt.seq DESC
    ) prev
    OUTER APPLY (
      SELECT TOP 1 nt.topic_id, nt.topic_title, nt.lesson_id, nt.module_id
      FROM NavigableTopics nt
      WHERE nt.seq > (SELECT seq FROM CurrentSeq)
      ORDER BY nt.seq ASC
    ) nxt
    WHERE t.topic_id = @topic_id;

    SET @result_code    = 0;
    SET @result_message = 'Topic details retrieved successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
