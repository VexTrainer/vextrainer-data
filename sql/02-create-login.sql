-- =============================================
-- VexTrainer Security Setup Script
-- Description: Creates application logins, database users,
--              and role-based access control.
-- Security Model:
--   - Two SQL logins with clearly separated responsibilities:
--       vextrainer01_dbo      ? DDL owner account, creates and
--                             manages all database objects
--       vextrainer01_teacher ? Application runtime account,
--                             executes stored procedures only
--   - All database objects owned by dbo schema
--   - No direct table/view permissions granted to anyone
--   - All data access goes through stored procedures only
--   - EXECUTE permissions on stored procedures granted to
--     'staff' role (see individual stored procedure scripts)
-- =============================================

-- Switch context to master to create server-level logins
USE [master]
GO

-- -----------------------------------------------------
-- Login 1: vextrainer01_dbo
-- Purpose: DDL owner account used to create and manage
--          all database objects (tables, views, stored
--          procedures, indexes, constraints).
--          Never used by the application at runtime.
--          Use this login when running schema scripts
--          or making structural database changes.
-- -----------------------------------------------------
-- PASSWORD: Use a strong randomly generated password - never commit real password
-- DEFAULT_DATABASE: Login connects to VexTrainer01 by default
-- DEFAULT_LANGUAGE: US English for date/message formatting
-- CHECK_EXPIRATION OFF: Password expiration not enforced
--   (appropriate for administrative service accounts)
-- CHECK_POLICY OFF: Windows complexity policy not enforced
--   (ensure a strong password is used manually instead)
CREATE LOGIN [vextrainer01_dbo] WITH 
    PASSWORD = N'INSERT_STRONG_PASSWORD_HERE',
    DEFAULT_DATABASE = [VexTrainer01],
    DEFAULT_LANGUAGE = [us_english],
    CHECK_EXPIRATION = OFF,
    CHECK_POLICY = OFF
GO

-- -----------------------------------------------------
-- Login 2: vextrainer01_teacher
-- Purpose: Application runtime account used exclusively
--          by the API and web application to execute
--          stored procedures. Has no DDL privileges.
--          All application connection strings use this login.
-- -----------------------------------------------------
-- PASSWORD: Use a strong randomly generated at least 24 length password - never commit real password
CREATE LOGIN [vextrainer01_teacher] WITH 
    PASSWORD = N'INSERT_STRONG_PASSWORD_HERE',
    DEFAULT_DATABASE = [VexTrainer01],
    DEFAULT_LANGUAGE = [us_english],
    CHECK_EXPIRATION = OFF,
    CHECK_POLICY = OFF
GO

-- Switch context to VexTrainer01 application database
USE [VexTrainer01]
GO

-- -----------------------------------------------------
-- Database User: vextrainer01_dbo
-- Mapped to the vextrainer01_dbo server login.
-- Added to db_owner role to allow full DDL control:
--   CREATE/ALTER/DROP tables, views, stored procedures,
--   indexes, and all other database objects.
-- db_owner is the standard SQL Server role for this purpose.
-- -----------------------------------------------------
CREATE USER [vextrainer01_dbo]
    FOR LOGIN [vextrainer01_dbo]
    WITH DEFAULT_SCHEMA = [dbo]
GO

-- Grant basic connection rights to the application user
-- Without CONNECT, the user cannot access the database at all
GRANT CONNECT TO [vextrainer01_dbo]
GO

-- Grant db_owner role to vextrainer_dbo
-- db_owner members can perform all configuration and
-- maintenance activities on the database
ALTER ROLE [db_owner] ADD MEMBER [vextrainer01_dbo]
GO

-- -----------------------------------------------------
-- Database User: vextrainer01_teacher
-- Mapped to the vextrainer_teachers server login.
-- Granted only CONNECT rights - all other access is
-- controlled through the 'staff' role below.
-- -----------------------------------------------------
CREATE USER [vextrainer01_teacher] 
    FOR LOGIN [vextrainer01_teacher] 
    WITH DEFAULT_SCHEMA = [dbo]
GO

-- Grant basic connection rights to the application user
-- Without CONNECT, the user cannot access the database at all
GRANT CONNECT TO [vextrainer01_teacher]
GO

-- -----------------------------------------------------
-- Role: staff
-- Application runtime role assigned to vextrainer01_teacher.
-- EXECUTE permissions on stored procedures are granted
-- to this role (not directly to the user) so that
-- permissions can be managed at the role level.
-- To grant access to a new stored procedure:
--   GRANT EXECUTE ON [dbo].[procedure_name] TO [staff]
-- -----------------------------------------------------
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
-- - vextrainer_dbo is used only for schema changes, never in app connection strings
-- - vextrainer_teachers is used only in app connection strings, never for schema changes

-- Add vextrainer_teachers user to the staff role
-- Inherits all EXECUTE permissions granted to the staff role
ALTER ROLE [staff] ADD MEMBER [vextrainer01_teacher]
GO

-- END OF SCRIPT