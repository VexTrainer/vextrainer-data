SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_SubmitAnswer]
  @attempt_id          INT,
  @question_id         INT,
  @user_answer_json    NVARCHAR(MAX),
  @user_id             INT,
  @is_correct          BIT OUTPUT,
  @explanation         NVARCHAR(MAX) OUTPUT,
  @correct_answer_json NVARCHAR(MAX) OUTPUT,
  @current_score       DECIMAL(5,2) OUTPUT,
  @questions_answered  TINYINT OUTPUT,
  @result_code         INT OUTPUT,
  @result_message      NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_SubmitAnswer
  -- Purpose   : Evaluates a user's answer for one question within
  --             an active quiz attempt and records the result.
  --             Evaluation logic is branched by question_type_id:
  --               1 = Multiple choice, single answer
  --               2 = Multiple choice, multiple answers
  --               3 = Fill in the blank (case-insensitive trim)
  --               4 = True / False
  --               5 = Match pairs (placeholder — not yet implemented)
  --             After recording, the attempt's correct_answers
  --             counter and last_question_id are updated, and
  --             the running score and question count are returned.
  --             Answering the same question twice is rejected
  --             (result code 2) to prevent score manipulation.
  -- ============================================================
  -- Parameters:
  --   @attempt_id           - Active attempt ID (from sp_StartQuizAttempt)
  --   @question_id          - Question being answered
  --   @user_answer_json     - JSON payload; structure varies by type:
  --                           Type 1/4: {"answer_id": N}
  --                           Type 2:   {"answer_ids": [N, N, ...]}
  --                           Type 3:   {"text": "..."}
  --                           Type 5:   {"pairs": [...]}
  --   @user_id              - ID of the authenticated user (ownership check)
  --   @is_correct            OUT - 1 = correct, 0 = incorrect
  --   @explanation           OUT - Explanation text from t_question
  --   @correct_answer_json   OUT - Correct answer(s) as JSON
  --   @current_score         OUT - Running score for this attempt
  --   @questions_answered    OUT - Total questions answered so far
  --   @result_code           OUT - 0 = success, 1 = invalid/completed attempt,
  --                                2 = already answered, 99 = error
  --   @result_message        OUT - Human-readable outcome message
  -- ============================================================
  -- Result Codes:
  --   0  - Answer submitted and recorded successfully
  --   1  - Attempt not found, not owned by user, or already completed
  --   2  - This question has already been answered in this attempt
  --   99 - Unexpected SQL error (see @result_message)
  -- ============================================================
  SET NOCOUNT ON;
    BEGIN TRY
    DECLARE @question_type_id  TINYINT;
    DECLARE @point_value       DECIMAL(5,2);
    DECLARE @selected_answer_id INT;

    -- Validate attempt belongs to user and is still in progress
    IF NOT EXISTS (
      SELECT 1 FROM t_user_quiz_attempt
      WHERE attempt_id   = @attempt_id
        AND user_id      = @user_id
        AND is_completed = 0
    )
    BEGIN
      SET @result_code    = 1;
      SET @result_message = 'Invalid or completed attempt';
      RETURN;
    END

    -- Reject duplicate answer for the same question
    IF EXISTS (
      SELECT 1 FROM t_user_answer
      WHERE attempt_id = @attempt_id
        AND question_id = @question_id
    )
    BEGIN
      SET @result_code    = 2;
      SET @result_message = 'Question already answered';
      RETURN;
    END

    -- Load question metadata
    SELECT
      @question_type_id = question_type_id,
      @point_value      = point_value,
      @explanation      = explanation
    FROM t_question
    WHERE question_id = @question_id;

    -- -------------------------------------------------------
    -- Evaluate answer by question type
    -- -------------------------------------------------------

    IF @question_type_id = 1  -- Multiple choice: single answer
    BEGIN
      SET @selected_answer_id = JSON_VALUE(@user_answer_json, '$.answer_id');
      SELECT @is_correct = is_correct
      FROM t_answer
      WHERE answer_id = @selected_answer_id;
      SELECT @correct_answer_json = (
        SELECT answer_id FROM t_answer
        WHERE question_id = @question_id AND is_correct = 1
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      );
    END
    ELSE IF @question_type_id = 2  -- Multiple choice: multiple answers
    BEGIN
      -- Set-based comparison: order-independent, handles extras/omissions correctly.
      -- @matching_count = submitted IDs that are actually correct answers
      -- @correct_count  = total correct answers for this question
      -- @submitted_count = total IDs submitted by the user
      -- Correct only when all three match — no extras, no omissions.
      DECLARE @matching_count INT = (
        SELECT COUNT(*)
          FROM OPENJSON(@user_answer_json, '$.answer_ids') submitted
            JOIN t_answer a ON CAST(submitted.value AS INT) = a.answer_id
          WHERE a.question_id = @question_id AND a.is_correct = 1
      );
      DECLARE @correct_count INT = (
        SELECT COUNT(*)
		  FROM t_answer
          WHERE question_id = @question_id AND is_correct = 1
      );
      DECLARE @submitted_count INT = (
        SELECT COUNT(*)
		  FROM OPENJSON(@user_answer_json, '$.answer_ids')
      );
      SET @is_correct = CASE
        WHEN @matching_count  = @correct_count
         AND @submitted_count = @correct_count
        THEN 1 ELSE 0
      END;
      SELECT @correct_answer_json = (
        SELECT answer_id FROM t_answer
        WHERE question_id = @question_id AND is_correct = 1
        FOR JSON PATH
      );
    END
    ELSE IF @question_type_id = 3  -- Fill in the blank (case-insensitive)
    BEGIN
      DECLARE @user_text    NVARCHAR(500) = JSON_VALUE(@user_answer_json, '$.text');
      DECLARE @correct_text NVARCHAR(500);
      SELECT @correct_text = answer_text
      FROM t_answer
      WHERE question_id = @question_id AND is_correct = 1;
      SET @is_correct = CASE
        WHEN LOWER(LTRIM(RTRIM(@user_text))) = LOWER(LTRIM(RTRIM(@correct_text))) THEN 1
        ELSE 0
      END;
      SET @correct_answer_json = '{"text":"' + @correct_text + '"}';
    END
    ELSE IF @question_type_id = 4  -- True / False
    BEGIN
      SET @selected_answer_id = JSON_VALUE(@user_answer_json, '$.answer_id');
      SELECT @is_correct = is_correct
      FROM t_answer
      WHERE answer_id = @selected_answer_id;
      SELECT @correct_answer_json = (
        SELECT answer_id FROM t_answer
        WHERE question_id = @question_id AND is_correct = 1
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      );
    END
    ELSE IF @question_type_id = 5  -- Match pairs
        BEGIN
      -- Correctly matched pairs in the submission
      DECLARE @matched_pairs INT = (
        SELECT COUNT(*)
        FROM OPENJSON(@user_answer_json, '$.matches') WITH (
            left_id  INT '$.left',
            right_id INT '$.right'
        ) submitted
        INNER JOIN t_answer al ON al.answer_id    = submitted.left_id
                               AND al.question_id = @question_id
                               AND al.match_side  = 'L'
        INNER JOIN t_answer ar ON ar.answer_id    = submitted.right_id
                               AND ar.question_id = @question_id
                               AND ar.match_side  = 'R'
        WHERE al.match_pair_id = ar.match_pair_id
      );

      -- Total expected pairs (distinct match_pair_id on L side)
      DECLARE @total_pairs INT = (
        SELECT COUNT(DISTINCT match_pair_id)
        FROM t_answer
        WHERE question_id = @question_id
          AND match_side  = 'L'
      );

      -- Submitted pair count — must equal total (no extras, no omissions)
      DECLARE @submitted_pairs INT = (
        SELECT COUNT(*)
        FROM OPENJSON(@user_answer_json, '$.matches')
      );

      SET @is_correct = CASE
        WHEN @matched_pairs   = @total_pairs
         AND @submitted_pairs = @total_pairs
        THEN 1 ELSE 0
      END;

      -- Return correct pairings as JSON for the client answer-key display
      SELECT @correct_answer_json = (
        SELECT
            al.answer_id AS left_id,
            ar.answer_id AS right_id
        FROM t_answer al
        INNER JOIN t_answer ar ON ar.match_pair_id = al.match_pair_id
                               AND ar.question_id  = al.question_id
                               AND ar.match_side   = 'R'
        WHERE al.question_id = @question_id
          AND al.match_side  = 'L'
        ORDER BY al.match_pair_id
        FOR JSON PATH
      );
    END

    -- Default to incorrect if evaluation branch left @is_correct NULL
    SET @is_correct = ISNULL(@is_correct, 0);

    -- Record the answer
    INSERT t_user_answer (attempt_id, question_id, user_answer_json, is_correct)
    VALUES (@attempt_id, @question_id, @user_answer_json, @is_correct);

    -- Update attempt counters
    UPDATE t_user_quiz_attempt
    SET
      correct_answers  = correct_answers + CASE WHEN @is_correct = 1 THEN 1 ELSE 0 END,
      last_question_id = @question_id
    WHERE attempt_id = @attempt_id;

    -- Return running score and question count for this attempt
    SELECT
      @current_score      = CAST(SUM(CASE WHEN ua.is_correct = 1 THEN q.point_value ELSE 0 END) AS DECIMAL(5,2)),
      @questions_answered = COUNT(*)
    FROM t_user_answer ua
    INNER JOIN t_question q ON q.question_id = ua.question_id
    WHERE ua.attempt_id = @attempt_id;

    SET @result_code    = 0;
    SET @result_message = 'Answer submitted successfully';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
