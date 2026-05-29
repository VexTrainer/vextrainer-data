SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_GetBookmarks]
  @user_id        INT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetBookmarks
  -- Purpose   : Returns user's bookmarks:
  -- ============================================================
  -- Parameters:
  --   @user_id       - ID of the authenticated user
  --   @result_code    OUT - 0 = success, 99 = error
  --   @result_message OUT - Human-readable outcome message
    -- ============================================================
  -- Result Codes:
  --   0  - Data retrieved successfully
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;
  BEGIN TRY
    SELECT m.module_id  AS moduleId,
	       m.module_name AS moduleName,
		   l.lesson_id AS lessonId,
		   l.lesson_title AS lessonTitle,
		   t.topic_id AS topicId,
		   t.topic_title AS topicTitle
    FROM t_bookmark b
	  JOIN t_topic t ON b.topic_id = t.topic_id
	  JOIN t_lesson l ON t.lesson_id = l.lesson_id
	  JOIN t_module m ON l.module_id = m.module_id
    WHERE b.user_id = @user_id
	  ORDER BY m.module_id, l.lesson_id, t.topic_id;

    SET @result_code    = 0;
    SET @result_message = 'Bookmarks retrieved successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
