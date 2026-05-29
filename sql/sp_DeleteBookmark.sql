SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_DeleteBookmark]
  @user_id        INT,
  @topic_id       INT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_DeleteBookmark
  -- Purpose   : Delete a user's bookmark:
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
    DELETE t_bookmark WHERE user_id = @user_id AND topic_id = @topic_id
    SET @result_code    = 0;
    SET @result_message = 'Bookmarks deleted successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
