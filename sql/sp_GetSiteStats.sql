SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetSiteStats]
AS
BEGIN
-- ============================================================
-- Procedure : sp_GetSiteStats
-- Purpose   : Returns the cached site-wide aggregate metrics
--             from t_site_stats (single row, always stats_id=1).
--             Called by the public home page — no auth required.
--             Refresh the underlying data by running
-- ============================================================
    SET NOCOUNT ON;
    SELECT
        total_modules AS TotalModules,
        total_lessons AS TotalLessons,
        total_topics  AS TotalTopics,
        students      AS Students,
        topics_read   AS TopicsRead
    FROM  [dbo].[t_site_stats]
    WHERE stats_id = 1;
END
GO

--END OF SCRIPT
