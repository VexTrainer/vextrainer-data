SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_ConfirmAccountDeletion]
  @token          VARCHAR(255),
  @deleted_email  VARCHAR(254) OUTPUT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_ConfirmAccountDeletion
  -- Purpose   : Finalizes an account deletion request initiated
  --             upstream. Validates the one-time deletion token,
  --             then atomically: marks the token used, revokes
  --             all active sessions, and anonymizes the user
  --             record (soft-delete via field obfuscation).
  --             On any error the transaction is rolled back and
  --             the token is un-marked so the user can retry.
  -- ============================================================
  -- Parameters:
  --   @token         - One-time deletion token from the confirmation link
  --   @deleted_email  OUT - Email address that was anonymized (for
  --                         post-deletion notification by the caller)
  --   @result_code    OUT - 0 = success, 1 = invalid/expired token
  --                         or unexpected error, 99 = SQL error
  --   @result_message OUT - Human-readable outcome message
  -- ============================================================
  -- Result Codes:
  --   0  - Account anonymized and sessions revoked successfully
  --   1  - Token not found, already used, expired, or orphaned;
  --         also returned on unexpected error (with retry message)
  --   99 - Unexpected SQL error surfaced outside the retry path
  -- ============================================================
  -- Anonymization Strategy (soft-delete):
  --   email         -> 'x' + original email  (preserves uniqueness)
  --   password_hash -> ''                    (satisfies NOT NULL)
  --   user_name     -> 'deleted_<user_id>'
  --   is_active     -> 0
  -- ============================================================
  SET NOCOUNT ON;
  SET @deleted_email = NULL;
  BEGIN TRY
    DECLARE @request_id INT, @user_id INT, @email NVARCHAR(254);

    -- Validate token: must be unused, unexpired, and tied to a real user
    SELECT
      @request_id = id,
      @user_id    = user_id,
      @email      = email
    FROM t_account_deletion_requests
    WHERE token      = @token
      AND used_at    IS NULL
      AND expires_at > GETUTCDATE()
      AND user_id    IS NOT NULL;

    IF @request_id IS NULL
    BEGIN
      SET @result_code    = 1;
      SET @result_message = 'This link is invalid or has expired.';
      RETURN;
    END

    BEGIN TRANSACTION;

      -- Mark token used to prevent replay
      UPDATE t_account_deletion_requests
      SET used_at = GETUTCDATE()
      WHERE id = @request_id;

      -- Revoke all active sessions
      DELETE t_session
      WHERE user_id = @user_id;

      -- Anonymize user record (soft-delete)
      UPDATE t_user
      SET
        email         = LEFT('x' + CAST(DATEDIFF_BIG(MILLISECOND, '1970-01-01', SYSUTCDATETIME()) AS VARCHAR(24)) + email, 254),
        password_hash = '',
        user_name     = CONCAT('deleted_', @user_id),
        is_active     = 0
      WHERE user_id = @user_id;

    COMMIT TRANSACTION;

    SET @deleted_email  = @email;
    SET @result_code    = 0;
    SET @result_message = 'Your account has been successfully deleted.';
  END TRY
  BEGIN CATCH
    -- Roll back all changes atomically
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    -- Un-mark token so the user can retry
    IF @request_id IS NOT NULL
      UPDATE t_account_deletion_requests
      SET used_at = NULL
      WHERE id = @request_id;

    SET @result_code    = 1;
    SET @result_message = 'An error occurred while deleting your account. Please try again.';
  END CATCH
END
GO

