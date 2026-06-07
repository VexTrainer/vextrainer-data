SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetCategoriesPaged]
  @offset         INT = 0,        -- number of parent categories to skip
  @page_size      INT = 14,       -- number of parent categories to return
  @has_more       BIT OUTPUT,     -- 1 if more parent categories exist after this page
  @result_code    INT OUTPUT,
  @result_message NVARCHAR(500) OUTPUT
AS
BEGIN
  -- ============================================================
  -- Procedure : sp_GetCategoriesPaged
  -- Purpose   : Returns N parent categories starting at @offset,
  --             plus all their subcategories, in a single flat
  --             result set. The client assembles the hierarchy
  --             in memory (same as sp_GetCategories).
  --             @has_more tells the client whether to show a
  --             "Load more" button.
  --             Paging is by parent category count, not row count.
  -- ============================================================
  -- Parameters:
  --   @offset       - Parent categories to skip (0 = first page)
  --   @page_size    - Parent categories per page (default 10)
  --   @has_more OUT - 1 if additional parent categories exist
  --   @result_code    OUT - 0 = success, 99 = error
  --   @result_message OUT - Human-readable outcome
  -- ============================================================
  -- Result Set (flat, same structure as sp_GetCategories):
  --   CategoryId         SMALLINT
  --   ParentCategoryId   SMALLINT  NULL for top-level
  --   CategoryName       VARCHAR
  --   DisplayOrder       SMALLINT
  -- ============================================================
  SET NOCOUNT ON;
  BEGIN TRY

    -- Page the parent categories by display_order then name
    WITH paged_parents AS (
        SELECT category_id
        FROM   t_category
        WHERE  is_active          = 1
          AND  parent_category_id IS NULL
        ORDER BY display_order, category_name
        OFFSET @offset ROWS FETCH NEXT @page_size ROWS ONLY
    )
    -- Return those parents + all their subcategories in one set.
    -- Ordered so each parent is immediately followed by its children.
    SELECT
        c.category_id        AS CategoryId,
        c.parent_category_id AS ParentCategoryId,
        c.category_name      AS CategoryName,
        c.display_order      AS DisplayOrder
    FROM  t_category c
    WHERE c.is_active = 1
      AND (
              c.category_id        IN (SELECT category_id FROM paged_parents)
           OR c.parent_category_id IN (SELECT category_id FROM paged_parents)
          )
    ORDER BY
        COALESCE(c.parent_category_id, c.category_id),   -- group children under parent
        CASE WHEN c.parent_category_id IS NULL THEN 0 ELSE 1 END,  -- parent before children
        c.display_order,
        c.category_name;

    -- Determine whether more parent categories exist after this page
    SET @has_more = CASE
        WHEN (
            SELECT COUNT(*)
            FROM   t_category
            WHERE  is_active = 1 AND parent_category_id IS NULL
        ) > @offset + @page_size
        THEN 1 ELSE 0
    END;

    SET @result_code    = 0;
    SET @result_message = 'Categories retrieved successfully';

  END TRY
  BEGIN CATCH
    SET @has_more       = 0;
    SET @result_code    = 99;
    SET @result_message = ERROR_MESSAGE();
  END CATCH
END
GO

--END OF SCRIPT
