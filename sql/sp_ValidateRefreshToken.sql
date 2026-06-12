USE [VexTrainer]
GO
SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_ValidateRefreshToken]
  @refresh_token  VARCHAR(512),
  @user_id        INT OUTPUT,
  @user_name      NVARCHAR(96) OUTPUT,
  @role_name         VARCHAR(64) OUTPUT,
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_ValidateRefreshToken
  -- Purpose   : Validates a refresh token and returns user
  --             identity WITHOUT rotating or updating anything.
  --             Called by the API before generating the real
  --             access token so GenerateAccessToken receives
  --             actual user data, not placeholder values.
  --             sp_RefreshToken is then called with the real
  --             access token to complete the rotation.
  -- ============================================================
  -- Parameters:
  --   @refresh_token  - Refresh token to validate
  --   @user_id   OUT  - User ID if token is valid
  --   @user_name OUT  - User name if token is valid
  --   @result_code    OUT - 0 = valid, 1 = invalid/expired, 99 = error
  --   @result_message OUT - Human-readable outcome
  -- ============================================================
  SET NOCOUNT ON;
  BEGIN TRY
    SELECT
      @user_id   = u.user_id,
      @user_name = u.user_name,
      @role_name = r.role_name
    FROM  t_session s
      INNER JOIN t_user u ON u.user_id = s.user_id
      INNER JOIN t_role r ON r.role_id = u.role_id
	WHERE s.refresh_token = @refresh_token
      AND s.is_active      = 1
      AND u.is_active      = 1;

    IF @user_id IS NULL
    BEGIN
      SET @result_code    = 1;
      SET @result_message = 'Invalid or expired refresh token';
      RETURN;
    END

    SET @result_code    = 0;
    SET @result_message = 'Refresh token valid';
  END TRY
  BEGIN CATCH
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
