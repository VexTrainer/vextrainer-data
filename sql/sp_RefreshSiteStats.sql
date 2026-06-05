SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_RefreshSiteStats]
AS
BEGIN
-- ============================================================
-- Procedure : sp_RefreshSiteStats
-- Purpose   : Refreshes the single-row stats cache.
--             Schedule via SQL Agent every 6 hours.
--             Safe to run manually at any time.
-- ============================================================
    SET NOCOUNT ON;
    UPDATE [dbo].[t_site_stats]
    SET
        total_modules = (SELECT COUNT(1) FROM t_module WHERE is_active = 1),
        total_lessons = (SELECT COUNT(1) FROM t_lesson WHERE is_active = 1),
        total_topics  = (SELECT COUNT(1) FROM t_topic  WHERE is_active = 1),
        students      = (SELECT COUNT(1) FROM t_user   WHERE is_active = 1),
        topics_read   = (SELECT COUNT(1) FROM t_user_topic_read),
        last_updated  = GETUTCDATE()
    WHERE stats_id = 1;
END
GO

--END OF SCRIPT
