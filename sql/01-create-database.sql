-- =============================================
-- VexTrainer Database Creation Script
-- Description: Creates and configures the VexTrainer 
--              SQL Server database with all required settings
-- Note: File paths are environment-specific. Update
--       FILENAME values to match your server configuration.
-- =============================================

-- Switch context to master database before creating a new database
USE [master]
GO

-- Create the VexTrainer database with explicit file specifications
-- CONTAINMENT = NONE: Database does not manage its own logins (server-level auth)
-- PRIMARY filegroup hosts the main data file (.mdf)
-- SIZE = 2GB: Initial data file size pre-allocated for performance
-- MAXSIZE = UNLIMITED: Data file can grow without an upper bound
-- FILEGROWTH = 128MB: Data file grows in 128MB increments to reduce fragmentation
-- LOG ON: Transaction log file stored separately (best practice - different drive)
-- Log SIZE = 2GB, MAXSIZE = 2GB: Log file capped to prevent runaway growth
-- FILEGROWTH = 0KB: Log auto-growth disabled - size must be managed manually
-- CATALOG_COLLATION = DATABASE_DEFAULT: System catalog uses database collation
CREATE DATABASE [VexTrainer01]
 CONTAINMENT = NONE
 ON PRIMARY 
( NAME = N'VexTrainer01', FILENAME = N'e:\mssql-data\VexTrainer01.mdf', SIZE = 2GB, MAXSIZE = UNLIMITED, FILEGROWTH = 128MB )
 LOG ON 
( NAME = N'VexTrainer01_log', FILENAME = N'f:\mssql-log\VexTrainer01_log.ldf', SIZE = 2GB, MAXSIZE = 2GB, FILEGROWTH = 0KB )
  COLLATE SQL_Latin1_General_CP1_CI_AS WITH CATALOG_COLLATION = DATABASE_DEFAULT
GO

-- ANSI_NULL_DEFAULT OFF: Columns without explicit NULL/NOT NULL default to NOT NULL
-- (ANSI standard would default to NULL - turning off for stricter data integrity)
ALTER DATABASE [VexTrainer01] SET ANSI_NULL_DEFAULT OFF
GO

-- ANSI_NULLS OFF: Allows non-ANSI NULL comparisons (= NULL instead of IS NULL)
-- Note: Future versions of SQL Server will always enforce ANSI_NULLS ON
ALTER DATABASE [VexTrainer01] SET ANSI_NULLS OFF
GO

-- ANSI_PADDING OFF: Trailing spaces trimmed from varchar, trailing zeros from varbinary
-- Controls how values shorter than column size are stored
ALTER DATABASE [VexTrainer01] SET ANSI_PADDING OFF
GO

-- ANSI_WARNINGS OFF: Suppresses ISO standard warnings for divide-by-zero
-- and NULL values in aggregate functions (SUM, AVG etc.)
ALTER DATABASE [VexTrainer01] SET ANSI_WARNINGS OFF
GO

-- ARITHABORT OFF: Query does not terminate on divide-by-zero or overflow errors
-- Note: When ANSI_WARNINGS is ON, this setting is effectively ON regardless
ALTER DATABASE [VexTrainer01] SET ARITHABORT OFF
GO

-- AUTO_CLOSE OFF: Database remains open after last user disconnects
-- ON would free resources but cause slow reconnection - OFF is correct for a server
ALTER DATABASE [VexTrainer01] SET AUTO_CLOSE OFF
GO

-- AUTO_SHRINK OFF: Prevents SQL Server from automatically shrinking database files
-- Auto-shrink causes fragmentation and performance issues - always disable on production
ALTER DATABASE [VexTrainer01] SET AUTO_SHRINK OFF
GO

-- AUTO_UPDATE_STATISTICS ON: SQL Server automatically updates query optimization 
-- statistics when data changes significantly - critical for query performance
ALTER DATABASE [VexTrainer01] SET AUTO_UPDATE_STATISTICS ON
GO

-- CURSOR_CLOSE_ON_COMMIT OFF: Cursors remain open after a transaction commits
-- ON would close cursors automatically on COMMIT or ROLLBACK
ALTER DATABASE [VexTrainer01] SET CURSOR_CLOSE_ON_COMMIT OFF
GO

-- CURSOR_DEFAULT GLOBAL: Cursors are accessible across the entire connection scope
-- LOCAL would restrict cursor visibility to the stored procedure or batch that created it
ALTER DATABASE [VexTrainer01] SET CURSOR_DEFAULT GLOBAL
GO

-- CONCAT_NULL_YIELDS_NULL OFF: Concatenating NULL with a string returns the string
-- (e.g., 'VexTrainer' + NULL = 'VexTrainer' instead of NULL)
-- Note: ANSI standard behavior would yield NULL - this is a compatibility setting
ALTER DATABASE [VexTrainer01] SET CONCAT_NULL_YIELDS_NULL OFF
GO

-- NUMERIC_ROUNDABORT OFF: Query does not terminate when rounding causes loss of precision
-- ON would raise an error on precision loss in numeric operations
ALTER DATABASE [VexTrainer01] SET NUMERIC_ROUNDABORT OFF
GO

-- QUOTED_IDENTIFIER OFF: Double quotes treated as string delimiters, not object identifiers
-- When OFF, use square brackets [] for object names with spaces or reserved words
ALTER DATABASE [VexTrainer01] SET QUOTED_IDENTIFIER OFF
GO

-- RECURSIVE_TRIGGERS OFF: Prevents triggers from firing themselves recursively
-- Recursive triggers can cause infinite loops if not carefully controlled
ALTER DATABASE [VexTrainer01] SET RECURSIVE_TRIGGERS OFF
GO

-- DISABLE_BROKER: Turns off SQL Server Service Broker (async messaging system)
-- Not needed for VexTrainer - disabling reduces overhead
ALTER DATABASE [VexTrainer01] SET DISABLE_BROKER
GO

-- AUTO_UPDATE_STATISTICS_ASYNC OFF: Statistics updates happen synchronously
-- Queries wait for updated statistics before executing (more accurate query plans)
-- ASYNC ON would update in background but queries might use stale statistics
ALTER DATABASE [VexTrainer01] SET AUTO_UPDATE_STATISTICS_ASYNC OFF
GO

-- DATE_CORRELATION_OPTIMIZATION OFF: SQL Server does not maintain correlation 
-- statistics between date-correlated tables - not needed for this application
ALTER DATABASE [VexTrainer01] SET DATE_CORRELATION_OPTIMIZATION OFF
GO

-- TRUSTWORTHY OFF: Database cannot access resources outside its own scope
-- Prevents potentially dangerous cross-database permission chains - security best practice
ALTER DATABASE [VexTrainer01] SET TRUSTWORTHY OFF
GO

-- ALLOW_SNAPSHOT_ISOLATION OFF: Disables snapshot-based transaction isolation
-- Snapshot isolation uses row versioning in tempdb - not required for this workload
ALTER DATABASE [VexTrainer01] SET ALLOW_SNAPSHOT_ISOLATION OFF
GO

-- PARAMETERIZATION SIMPLE: SQL Server parameterizes only simple queries automatically
-- FORCED would parameterize all queries - SIMPLE is appropriate default
ALTER DATABASE [VexTrainer01] SET PARAMETERIZATION SIMPLE
GO

-- READ_COMMITTED_SNAPSHOT OFF: Standard locking behavior for READ COMMITTED isolation
-- ON would use row versioning instead of locks - OFF is appropriate here
-- since ALLOW_SNAPSHOT_ISOLATION is also OFF
ALTER DATABASE [VexTrainer01] SET READ_COMMITTED_SNAPSHOT OFF
GO

-- HONOR_BROKER_PRIORITY OFF: All Service Broker conversations treated equally
-- Not relevant since broker is disabled above
ALTER DATABASE [VexTrainer01] SET HONOR_BROKER_PRIORITY OFF
GO

-- RECOVERY FULL: Complete transaction log retention until explicit log backup
-- Enables point-in-time restore - recommended for production databases
-- Requires regular transaction log backups to prevent log file from growing unbounded
ALTER DATABASE [VexTrainer01] SET RECOVERY FULL
GO

-- MULTI_USER: Database allows multiple simultaneous connections (normal operating mode)
-- Alternatives: SINGLE_USER (maintenance) or RESTRICTED_USER (admins only)
ALTER DATABASE [VexTrainer01] SET MULTI_USER
GO

-- PAGE_VERIFY CHECKSUM: SQL Server computes and stores a checksum for each data page
-- Detects I/O path corruption when pages are read back - recommended for all databases
ALTER DATABASE [VexTrainer01] SET PAGE_VERIFY CHECKSUM
GO

-- DB_CHAINING OFF: Cross-database ownership chaining disabled
-- Prevents objects in this database from accessing other databases via ownership chain
-- Security best practice - enable only if explicitly needed
ALTER DATABASE [VexTrainer01] SET DB_CHAINING OFF
GO

-- FILESTREAM NON_TRANSACTED_ACCESS = OFF: Disables non-transactional FILESTREAM access
-- FILESTREAM stores large binary data (images, files) in the filesystem
-- Not used in VexTrainer - disabled for security
ALTER DATABASE [VexTrainer01] SET FILESTREAM(NON_TRANSACTED_ACCESS = OFF)
GO

-- TARGET_RECOVERY_TIME = 60 SECONDS: SQL Server targets database recovery 
-- within 60 seconds after a crash by controlling checkpoint frequency
ALTER DATABASE [VexTrainer01] SET TARGET_RECOVERY_TIME = 60 SECONDS
GO

-- DELAYED_DURABILITY = DISABLED: All transactions are fully durable
-- Data is written to disk before COMMIT returns - no data loss risk
-- FORCED or ALLOWED delayed durability trades durability for performance
ALTER DATABASE [VexTrainer01] SET DELAYED_DURABILITY = DISABLED
GO

-- ACCELERATED_DATABASE_RECOVERY = OFF: Uses traditional recovery mechanism
-- ADR (introduced in SQL Server 2019) speeds up recovery and rollback
-- Can be enabled later if recovery time becomes a concern
ALTER DATABASE [VexTrainer01] SET ACCELERATED_DATABASE_RECOVERY = OFF
GO

-- QUERY_STORE = ON: Enables Query Store for query performance monitoring
-- Tracks query execution plans and runtime statistics over time
-- Useful for identifying regressed queries and plan forcing
-- OPERATION_MODE = READ_WRITE: Actively collects and stores query data
ALTER DATABASE [VexTrainer01] SET QUERY_STORE = ON
GO

ALTER DATABASE [VexTrainer01] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,        -- Actively collect query data
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30), -- Retain 30 days of data
    DATA_FLUSH_INTERVAL_SECONDS = 900,  -- Flush in-memory data to disk every 15 min
    INTERVAL_LENGTH_MINUTES = 60,       -- Aggregate stats in 60-minute intervals
    MAX_STORAGE_SIZE_MB = 100,          -- Cap Query Store storage at 100MB
    QUERY_CAPTURE_MODE = AUTO,          -- Capture relevant queries automatically
    SIZE_BASED_CLEANUP_MODE = AUTO      -- Auto-cleanup when storage limit approached
)
GO

-- READ_WRITE: Sets database to read-write mode (normal operating mode)
-- Final statement confirms database is fully operational for all users
ALTER DATABASE [VexTrainer01] SET READ_WRITE
GO


