SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_MarkTopicRead]
  @user_id        INT,
  @topic_id       INT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    -- Validate topic exists and is active
    IF NOT EXISTS (SELECT 1 FROM t_topic WHERE topic_id = @topic_id AND is_active = 1)
    BEGIN
      SET @result_code    = 1;
      SET @result_message = 'Topic not found';
      RETURN;
    END

    -- Upsert: refresh read_date on revisit, insert on first read
    UPDATE t_user_topic_read
       SET read_date = GETUTCDATE()
     WHERE user_id  = @user_id
       AND topic_id = @topic_id;

    IF @@ROWCOUNT = 0
      INSERT t_user_topic_read (user_id, topic_id) VALUES (@user_id, @topic_id);

    -- Auto-complete lesson if all its topics are now read
    DECLARE @lesson_id      INT;

    SELECT @lesson_id = lesson_id
      FROM t_topic
     WHERE topic_id = @topic_id;

    IF (SELECT COUNT(*) FROM t_topic WHERE lesson_id = @lesson_id AND is_active = 1)
       =
       (SELECT COUNT(*) FROM t_user_topic_read utr
          JOIN t_topic t ON t.topic_id = utr.topic_id
         WHERE utr.user_id = @user_id
           AND t.lesson_id = @lesson_id
           AND t.is_active = 1)
    BEGIN
      UPDATE t_user_lesson_read
         SET read_date = GETUTCDATE()
       WHERE user_id   = @user_id
         AND lesson_id = @lesson_id;

      IF @@ROWCOUNT = 0
        INSERT t_user_lesson_read (user_id, lesson_id) VALUES (@user_id, @lesson_id);
    END

    SET @result_code    = 0;
    SET @result_message = 'Topic marked as read';

  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
