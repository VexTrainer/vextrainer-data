-- =============================================
-- VexTrainer Security Setup Script
-- Description: Creates application login, database user,
--              and role-based access control for teachers/staff.
-- Security Model:
--   - Application connects via 'vextrainer_teachers' SQL login
--   - All database objects owned by dbo
--   - No direct table/view permissions granted to anyone
--   - All data access goes through stored procedures only
--   - Stored procedure EXECUTE permissions granted to 'staff' role
-- =============================================

-- Switch context to master to create server-level login
USE [master]
GO

-- Create SQL Server login for the application's teacher/staff connection
-- PASSWORD: Use a strong randomly generated password - never commit real password
-- DEFAULT_DATABASE: Login connects to VexTrainer01 by default
-- DEFAULT_LANGUAGE: US English for date/message formatting
-- CHECK_EXPIRATION OFF: Password expiration policy not enforced
--   (appropriate for application service accounts)
-- CHECK_POLICY OFF: Windows password complexity policy not enforced
--   (ensure a strong password is used manually instead)
CREATE LOGIN [vextrainer_teachers] WITH 
    PASSWORD = N'INSERT_STRONG_PASSWORD_HERE',
    DEFAULT_DATABASE = [VexTrainer01],
    DEFAULT_LANGUAGE = [us_english],
    CHECK_EXPIRATION = OFF,
    CHECK_POLICY = OFF
GO

-- Switch context to VexTrainer01 application database
USE [VexTrainer01]
GO

-- Create database user mapped to the server login created above
-- DEFAULT_SCHEMA = dbo: User resolves unqualified object names under dbo schema
CREATE USER [vextrainer_teachers] 
    FOR LOGIN [vextrainer_teachers] 
    WITH DEFAULT_SCHEMA = [dbo]
GO

-- Grant basic connection rights to the database user
-- Without CONNECT, the user cannot access the database at all
GRANT CONNECT TO [vextrainer_teachers]
GO

-- Create the 'staff' database role
-- Role-based access control allows permissions to be managed at role level
-- Add or remove members without changing individual permissions
CREATE ROLE [staff]
GO

-- Security design notes:
-- - No permissions granted directly on any table or view to any user or role
-- - All database objects are owned by dbo
-- - Access to data is exclusively through stored procedures
-- - EXECUTE permission on stored procedures must be granted to this role
--   separately for each procedure (see individual stored procedure scripts)
-- - This pattern prevents direct table access and enforces business logic
--   through the stored procedure layer

-- Add vextrainer_teachers user to the staff role
-- Inherits all permissions granted to the staff role
ALTER ROLE [staff] ADD MEMBER [vextrainer_teachers]
GO
