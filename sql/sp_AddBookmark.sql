SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_AddBookmark]
  @user_id        INT,
  @topic_id       INT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_AddBookmark
  -- Purpose   : Adds a topic as user's bookmark:
  -- ============================================================
  -- Parameters:
  --   @user_id       - ID of the authenticated user
  --   @topic_id      - Topic ID
  --   @result_code    OUT - 0 = success, 99 = error
  --   @result_message OUT - Human-readable outcome message
    -- ============================================================
  -- Result Codes:
  --   0  - Data retrieved successfully
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;
  BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM t_user u WHERE u.user_id = @user_id)
    BEGIN
      SET @result_code = 1;
      SET @result_message = 'Invalid user.';
      RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM t_topic t WHERE t.topic_id = @topic_id)
    BEGIN
      SET @result_code = 2;
      SET @result_message = 'Invalid topic.';
      RETURN;
    END
	IF NOT EXISTS (SELECT 1 FROM t_bookmark b WHERE b.user_id = @user_id AND b.topic_id = @topic_id)
      INSERT t_bookmark (user_id, topic_id) VALUES (@user_id, @topic_id);

    SET @result_code    = 0;
    SET @result_message = 'Bookmarks added successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
