/*
=================================================================
VexTrainer Database - Table Creation Script
Description: Creates all application tables, constraints,
             indexes and default values for the VexTrainer
             platform. Supports lesson reading on web and
             lesson/quiz functionality on mobile apps.

Design Principles:
  - All objects owned by dbo schema
  - No direct table/view permissions - access via stored procedures only
  - UTC timestamps used throughout for timezone consistency
  - Role-based access control via t_role and t_user.role_id
  - Non-IDENTITY PKs on reference/content tables (module, lesson,
    topic, role) - IDs are manually assigned and meaningful
  - IDENTITY PKs on transactional/user activity tables

Naming Conventions:
  Tables:      t_{entity_name}
  Primary Key: pk_{table_name}_{column_name}
  Foreign Key: fk_{table_name}_{referenced_table}_{column_name}
  Unique Index: ndxu_{table_name}_{column_name}
  Index:       ndx_{table_name}_{column_name}
  Default:     df_{table_name}_{column_name}
=================================================================
*/

-- Ensures NULL comparisons follow ISO standard:
-- Expressions involving NULL yield NULL, not TRUE or FALSE
-- Example: NULL = NULL yields NULL, not TRUE
SET ANSI_NULLS ON
GO

-- QUOTED_IDENTIFIER is turned off at database level
-- so double quotes are not used as identifier delimiters here
-- Square brackets [] are used instead for all object names
--SET QUOTED_IDENTIFIER ON
--GO

-- =============================================================
-- t_role
-- Reference table defining user roles in the system.
-- Manually assigned role_id values (no IDENTITY) - IDs are
-- meaningful and stable (e.g. 1=Admin, 2=Student, 3=Teacher).
-- Small dataset - tinyint is sufficient (max 255 roles).
-- =============================================================
CREATE TABLE [dbo].[t_role](
    -- Unique role identifier - manually assigned, meaningful value
    [role_id]   [tinyint]     NOT NULL,
    -- Human-readable role name (e.g. 'Admin', 'Student', 'Teacher')
    [role_name] [varchar](64) NULL,
    -- Clustered PK - role lookup always by role_id
    CONSTRAINT pk_t_role_role_id PRIMARY KEY CLUSTERED ([role_id]),
    -- Role names must be unique across the system
    CONSTRAINT ndxu_t_role_role_name UNIQUE NONCLUSTERED ([role_name])
)
GO

-- =============================================================
-- t_user
-- Core user account table. Stores all registered users
-- regardless of role. Authentication is handled via
-- password_hash - plain text passwords are never stored.
-- user_id is manually assigned (no IDENTITY) - managed
-- by the application layer.
-- =============================================================
CREATE TABLE [dbo].[t_user](
    -- Unique user identifier - assigned in stored procedure
    [user_id]       [int]          NOT NULL,
    -- Username - max 24 chars, typically, First Name Last Name
    [user_name]     [varchar](24)  NOT NULL,
    -- Email address - max 254 chars per RFC 5321, must be unique
    [email]         [varchar](254) NOT NULL,
    -- Optional phone number - E.164 format max 15 digits + country code
    -- varchar(17) accommodates '+', country code, number and separators
    [phone]         [varchar](17)  NULL,
    -- Bcrypt/PBKDF2 hashed password - never store plain text
    -- varchar(255) accommodates all common hash algorithm outputs
    [password_hash] [varchar](255) NOT NULL,
    -- Account creation timestamp in UTC - defaults to current UTC time
    [created_date]  [datetime2](7) NOT NULL,
    -- Last successful login timestamp in UTC - NULL until first login
    [last_login_date] [datetime2](7) NULL,
    -- Account active flag - 0=inactive, 1=active
    -- Defaults to 0 (inactive) until email is verified
    [is_active]     [bit]          NOT NULL,
    -- Foreign key to t_role - defaults to 2 (Student role)
    [role_id]       [tinyint]      NOT NULL,
    -- Clustered PK - all user lookups by user_id
    CONSTRAINT pk_t_user_user_id PRIMARY KEY CLUSTERED ([user_id]),
    -- Email addresses must be unique - used for login and notifications
    CONSTRAINT ndxu_t_user_email UNIQUE NONCLUSTERED ([email])
)
GO

-- New accounts default to current UTC timestamp
ALTER TABLE [dbo].[t_user]
    ADD CONSTRAINT df_t_user_created_date DEFAULT (getutcdate()) FOR [created_date]
GO

-- New accounts default to inactive (0) pending email verification
ALTER TABLE [dbo].[t_user]
    ADD CONSTRAINT df_t_user_is_active DEFAULT ((0)) FOR [is_active]
GO

-- New accounts default to role_id 2 (Student)
ALTER TABLE [dbo].[t_user]
    ADD CONSTRAINT df_t_user_role_id DEFAULT ((2)) FOR [role_id]
GO

-- Non-unique index on phone to support phone-based lookups
-- Phone is optional so NULL values will be present
CREATE INDEX [ndx_t_user_phone] ON [dbo].[t_user] ([phone])
GO

-- =============================================================
-- t_session
-- Manages active user sessions via JWT access tokens and
-- refresh tokens. Each login creates a new session record.
-- Expired or logged-out sessions are marked inactive rather
-- than deleted to preserve audit history.
-- =============================================================
CREATE TABLE [dbo].[t_session](
    -- Auto-incrementing session identifier
    [session_id]        [int]          IDENTITY(1,1) NOT NULL,
    -- User this session belongs to
    [user_id]           [int]          NOT NULL,
    -- JWT access token - short-lived, used for API authentication
    -- varchar(255) accommodates standard JWT token lengths
    [token]             [varchar](255) NOT NULL,
    -- Refresh token - longer-lived, used to obtain new access tokens
    -- NULL until first token refresh occurs
    [refresh_token]     [varchar](255) NULL,
    -- Session creation timestamp in UTC
    [created_date]      [datetime2](7) NOT NULL,
    -- Access token expiry timestamp in UTC
    -- Controlled by Jwt:AccessTokenExpiryMinutes in appsettings
    [expiry_date]       [datetime2](7) NOT NULL,
    -- Timestamp of last token renewal via refresh token
    -- NULL until first renewal
    [last_renewed_date] [datetime2](7) NULL,
    -- Session active flag - set to 0 on logout or token expiry
    -- Defaults to 1 (active) on creation
    [is_active]         [bit]          NOT NULL,
    -- Client device information for security auditing
    -- Stores user agent string or device description
    [device_info]       [varchar](500) NULL,
    -- Clustered PK - session lookups always by session_id
    CONSTRAINT pk_t_session_session_id PRIMARY KEY CLUSTERED ([session_id]),
    -- Refresh tokens must be unique across all sessions
    CONSTRAINT ndxu_t_session_refresh_token UNIQUE NONCLUSTERED ([refresh_token]),
    -- Access tokens must be unique across all sessions
    CONSTRAINT ndxu_t_session_token UNIQUE NONCLUSTERED ([token])
)
GO

-- Session creation timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_session]
    ADD CONSTRAINT df_t_session_created_date DEFAULT (getutcdate()) FOR [created_date]
GO

-- Sessions are active by default on creation
ALTER TABLE [dbo].[t_session]
    ADD CONSTRAINT df_t_session_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Sessions belong to a valid user - cascade not used, 
-- deactivate sessions before deleting users
ALTER TABLE [dbo].[t_session]
    WITH CHECK ADD CONSTRAINT fk_t_session_t_user_user_id
    FOREIGN KEY ([user_id]) REFERENCES [dbo].[t_user] ([user_id])
GO

-- =============================================================
-- t_category
-- Hierarchical category structure for organizing quizzes.
-- Supports parent-child relationships via self-referencing FK
-- on parent_category_id. Top-level categories have NULL parent.
-- =============================================================
CREATE TABLE [dbo].[t_category](
    -- Auto-incrementing category identifier
    -- smallint sufficient - platform will not exceed 32,767 categories
    [category_id]        [smallint]     IDENTITY(1,1) NOT NULL,
    -- Parent category for hierarchical nesting
    -- NULL indicates a top-level category
    [parent_category_id] [smallint]     NULL,
    -- Display name of the category
    [category_name]      [varchar](100) NOT NULL,
    -- Optional longer description of the category
    [description]        [nvarchar](500) NULL,
    -- Controls category sort order in listings - defaults to 1
    [display_order]      [tinyint]      NULL,
    -- Active flag - inactive categories hidden from users
    [is_active]          [bit]          NULL,
    -- Clustered PK - category lookups always by category_id
    CONSTRAINT pk_t_category_category_id PRIMARY KEY CLUSTERED ([category_id])
)
GO

-- Categories default to display position 1
ALTER TABLE [dbo].[t_category]
    ADD CONSTRAINT df_t_category_display_order DEFAULT ((1)) FOR [display_order]
GO

-- Categories are active by default on creation
ALTER TABLE [dbo].[t_category]
    ADD CONSTRAINT df_t_category_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Self-referencing FK enables category hierarchy
-- Parent must exist before child can be created
ALTER TABLE [dbo].[t_category]
    WITH CHECK ADD CONSTRAINT fk_t_category_t_category_parent_category_id_category_id
    FOREIGN KEY ([parent_category_id]) REFERENCES [dbo].[t_category] ([category_id])
GO

-- =============================================================
-- t_module
-- Top-level content grouping for the VEX programming curriculum.
-- Each module covers a major topic area (e.g. Hardware Basics,
-- Autonomous Programming, PID Control). module_id is manually
-- assigned - IDs correspond to curriculum module numbers.
-- =============================================================
CREATE TABLE [dbo].[t_module](
    -- Manually assigned module identifier matching curriculum numbering
    -- (e.g. module 0, module 4, module 5)
    [module_id]   [smallint]      NOT NULL,
    -- Module display name shown to students
    [module_name] [varchar](100)  NOT NULL,
    -- Optional description of module content and learning objectives
    [description] [nvarchar](500) NULL,
    -- Controls module sort order in curriculum listing
    [display_order] [tinyint]     NULL,
    -- Active flag - inactive modules hidden from students
    [is_active]   [bit]           NULL,
    -- Clustered PK - module lookups always by module_id
    CONSTRAINT pk_t_module_module_id PRIMARY KEY CLUSTERED ([module_id]),
    -- Module names must be unique across the curriculum
    CONSTRAINT ndxu_t_module_module_name UNIQUE NONCLUSTERED ([module_name])
)
GO

-- Modules default to display position 1
ALTER TABLE [dbo].[t_module]
    ADD CONSTRAINT df_t_module_display_order DEFAULT ((1)) FOR [display_order]
GO

-- Modules are active by default on creation
ALTER TABLE [dbo].[t_module]
    ADD CONSTRAINT df_t_module_is_active DEFAULT ((1)) FOR [is_active]
GO

-- =============================================================
-- t_lesson
-- Individual lessons within a module. Each lesson maps to a
-- Markdown file in the vextrainer-content repository.
-- The file_name computed column automatically generates the
-- standardized filename from module_id and lesson_id.
-- lesson_id is manually assigned - IDs correspond to lesson
-- numbers within the curriculum.
-- =============================================================
CREATE TABLE [dbo].[t_lesson](
    -- Manually assigned lesson identifier matching curriculum numbering
    [lesson_id]     [smallint]     NOT NULL,
    -- Module this lesson belongs to
    [module_id]     [smallint]     NOT NULL,
    -- Lesson display title shown to students
    [lesson_title]  [varchar](200) NOT NULL,
    -- Controls lesson sort order within its module
    [display_order] [smallint]     NULL,
    -- Active flag - inactive lessons hidden from students
    [is_active]     [bit]          NULL,
    -- Computed column: generates standardized Markdown filename
    -- Format: {module_id_5digits}-{lesson_id_5digits}.md
    -- Example: module_id=4, lesson_id=12 → '00004-00012.md'
    -- Matches filenames in vextrainer-content repository
    [file_name] AS (
        right('00000' + CONVERT([varchar](5), [module_id]), 5)
        + '-'
        + right('00000' + CONVERT([varchar](5), [lesson_id]), 5)
        + '.md'
    ),
    -- Clustered PK - lesson lookups always by lesson_id
    CONSTRAINT pk_t_lesson_lesson_id PRIMARY KEY CLUSTERED ([lesson_id])
)
GO

-- Lessons default to display position 1
ALTER TABLE [dbo].[t_lesson]
    ADD CONSTRAINT df_t_lesson_display_order DEFAULT ((1)) FOR [display_order]
GO

-- Lessons are active by default on creation
ALTER TABLE [dbo].[t_lesson]
    ADD CONSTRAINT df_t_lesson_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Each lesson must belong to a valid module
ALTER TABLE [dbo].[t_lesson]
    WITH CHECK ADD CONSTRAINT fk_t_lesson_t_module_module_id_module_id
    FOREIGN KEY ([module_id]) REFERENCES [dbo].[t_module] ([module_id])
GO

-- =============================================================
-- t_topic
-- Represents individual sections/headings within a lesson.
-- Used to track reading progress at a granular level and to
-- build the lesson table of contents. Supports nested topics
-- via self-referencing parent_topic_id for sub-headings.
-- topic_id is manually assigned - corresponds to heading
-- sequence numbers within the lesson content.
-- =============================================================
CREATE TABLE [dbo].[t_topic](
    -- Manually assigned topic identifier
    [topic_id]       [int]          NOT NULL,
    -- Lesson this topic belongs to
    [lesson_id]      [smallint]     NOT NULL,
    -- Topic heading text as shown in table of contents
    [topic_title]    [varchar](200) NOT NULL,
    -- Markdown heading level (1=H1, 2=H2, 3=H3 etc.)
    -- Used to render hierarchical table of contents
    [heading_level]  [tinyint]      NOT NULL,
    -- Parent topic for nested headings (sub-sections)
    -- NULL indicates a top-level heading within the lesson
    [parent_topic_id] [int]         NULL,
    -- Controls topic sort order within the lesson
    [display_order]  [smallint]     NOT NULL,
    -- Active flag - inactive topics excluded from table of contents
    [is_active]      [bit]          NULL,
    -- Clustered PK - topic lookups always by topic_id
    CONSTRAINT pk_t_topic_topic_id PRIMARY KEY CLUSTERED ([topic_id])
)
GO

-- Topics are active by default on creation
ALTER TABLE [dbo].[t_topic]
    ADD CONSTRAINT df_t_topic_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Each topic must belong to a valid lesson
ALTER TABLE [dbo].[t_topic]
    WITH CHECK ADD CONSTRAINT fk_t_topic_t_lesson_lesson_id_lesson_id
    FOREIGN KEY ([lesson_id]) REFERENCES [dbo].[t_lesson] ([lesson_id])
GO

-- Self-referencing FK enables nested topic hierarchy
-- Parent topic must exist before child topic can be created
ALTER TABLE [dbo].[t_topic]
    WITH CHECK ADD CONSTRAINT fk_t_topic_t_topic_parent_topic_id_topic_id
    FOREIGN KEY ([parent_topic_id]) REFERENCES [dbo].[t_topic] ([topic_id])
GO

-- =============================================================
-- t_question_type
-- Reference table defining supported quiz question formats.
-- Examples: MultipleChoice, TrueFalse, Matching, FillInBlank.
-- question_type_id is manually assigned - stable IDs used
-- in application logic to drive quiz rendering behavior.
-- =============================================================
CREATE TABLE [dbo].[t_question_type](
    -- Manually assigned question type identifier
    -- Used in application code to determine rendering logic
    [question_type_id] [tinyint]    NOT NULL,
    -- Human-readable question type name
    [question_type]    [varchar](50) NOT NULL,
    -- Clustered PK - type lookups always by question_type_id
    CONSTRAINT pk_t_question_type_question_type_id PRIMARY KEY CLUSTERED ([question_type_id]),
    -- Question type names must be unique
    CONSTRAINT ndxu_t_question_type_question_type UNIQUE NONCLUSTERED ([question_type])
)
GO

-- =============================================================
-- t_question
-- Individual quiz questions. Each question belongs to one quiz
-- and has one question type. Supports optional images for
-- visual questions. The explanation field provides feedback
-- shown to students after answering.
-- Note: FK to t_quiz added after t_quiz table is created below.
-- =============================================================
CREATE TABLE [dbo].[t_question](
    -- Auto-incrementing question identifier
    [question_id]         [int]           IDENTITY(1,1) NOT NULL,
    -- Quiz this question belongs to
    [quiz_id]             [smallint]      NOT NULL,
    -- Question format type (MultipleChoice, TrueFalse etc.)
    [question_type_id]    [tinyint]       NOT NULL,
    -- Full question text - nvarchar supports Unicode for code samples
    -- and special characters in VEX programming content
    [question_text]       [nvarchar](max) NOT NULL,
    -- Optional path to question image stored on server
    -- NULL if question has no associated image
    [question_image_path] [varchar](500)  NULL,
    -- Order in which question appears during quiz attempt
    -- Defaults to 1 - updated when quiz is assembled
    [question_order]      [tinyint]       NULL,
    -- Points awarded for correct answer - defaults to 1.0
    -- decimal(5,2) supports fractional point values (e.g. 0.5, 2.5)
    [point_value]         [decimal](5, 2) NULL,
    -- Explanation shown to student after answering
    -- Provides educational context for correct/incorrect answers
    [explanation]         [nvarchar](max) NULL,
    -- Active flag - inactive questions excluded from quiz attempts
    [is_active]           [bit]           NULL,
    -- Visual display order independent of question_order
    [display_order]       [smallint]      NULL,
    -- Clustered PK - question lookups always by question_id
    CONSTRAINT pk_t_question_question_id PRIMARY KEY CLUSTERED ([question_id]),
    -- Composite unique constraint ensures question_id is unique per quiz
    CONSTRAINT ndxu_t_question_quiz_id_question_id UNIQUE NONCLUSTERED ([quiz_id], [question_id])
)
GO

-- Questions default to position 1 within their quiz
ALTER TABLE [dbo].[t_question]
    ADD CONSTRAINT df_t_question_question_order DEFAULT ((1)) FOR [question_order]
GO

-- Questions are active by default on creation
ALTER TABLE [dbo].[t_question]
    ADD CONSTRAINT df_t_question_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Questions default to 1.0 point value
ALTER TABLE [dbo].[t_question]
    ADD CONSTRAINT df_t_question_point_value DEFAULT ((1.0)) FOR [point_value]
GO

-- Each question must have a valid question type
ALTER TABLE [dbo].[t_question]
    WITH CHECK ADD CONSTRAINT fk_t_question_t_question_type_question_type_id
    FOREIGN KEY ([question_type_id]) REFERENCES [dbo].[t_question_type] ([question_type_id])
GO

-- =============================================================
-- t_quiz
-- A quiz is a collection of questions associated with a
-- category. Quizzes appear in the mobile app after students
-- complete related lessons. total_questions is denormalized
-- for performance - must stay in sync with actual question count.
-- =============================================================
CREATE TABLE [dbo].[t_quiz](
    -- Auto-incrementing quiz identifier
    -- smallint sufficient - platform will not exceed 32,767 quizzes
    [quiz_id]         [smallint]     IDENTITY(1,1) NOT NULL,
    -- Category this quiz belongs to
    [category_id]     [smallint]     NOT NULL,
    -- Quiz display title shown to students
    [quiz_title]      [varchar](200) NOT NULL,
    -- Denormalized question count for display purposes
    -- Must be kept in sync with actual rows in t_question
    [total_questions] [tinyint]      NOT NULL,
    -- Controls quiz sort order within its category
    [display_order]   [tinyint]      NULL,
    -- Active flag - inactive quizzes hidden from students
    [is_active]       [bit]          NULL,
    -- Quiz creation timestamp in UTC
    [created_date]    [datetime2](7) NULL,
    -- Clustered PK - quiz lookups always by quiz_id
    CONSTRAINT pk_t_quiz_quiz_id PRIMARY KEY CLUSTERED ([quiz_id])
)
GO

-- Quizzes default to display position 1
ALTER TABLE [dbo].[t_quiz]
    ADD CONSTRAINT df_t_quiz_display_order DEFAULT ((1)) FOR [display_order]
GO

-- Quizzes are active by default on creation
ALTER TABLE [dbo].[t_quiz]
    ADD CONSTRAINT df_t_quiz_is_active DEFAULT ((1)) FOR [is_active]
GO

-- Quiz creation timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_quiz]
    ADD CONSTRAINT df_t_quiz_created_date DEFAULT (getutcdate()) FOR [created_date]
GO

-- Each quiz must belong to a valid category
ALTER TABLE [dbo].[t_quiz]
    WITH CHECK ADD CONSTRAINT fk_t_quiz_t_category_category_id_category_id
    FOREIGN KEY ([category_id]) REFERENCES [dbo].[t_category] ([category_id])
GO

-- FK added here (after t_quiz creation) because t_question
-- is created before t_quiz - forward reference not possible in SQL Server
ALTER TABLE [dbo].[t_question]
    WITH CHECK ADD CONSTRAINT fk_t_question_t_quiz_quiz_id
    FOREIGN KEY ([quiz_id]) REFERENCES [dbo].[t_quiz] ([quiz_id])
GO

-- =============================================================
-- t_user_quiz_attempt
-- Records each time a student starts a quiz. Tracks progress
-- through the quiz (last_question_id), final score, and
-- completion status. Students may have multiple attempts
-- per quiz. Incomplete attempts are preserved to allow
-- resuming from last_question_id.
-- =============================================================
CREATE TABLE [dbo].[t_user_quiz_attempt](
    -- Auto-incrementing attempt identifier
    -- int used (not smallint) to support high volume of attempts
    -- across many users over the platform lifetime
    [attempt_id]      [int]           IDENTITY(1,1) NOT NULL,
    -- Student who made this attempt
    [user_id]         [int]           NOT NULL,
    -- Quiz being attempted
    [quiz_id]         [smallint]      NOT NULL,
    -- When the attempt was started - defaults to current UTC time
    [started_date]    [datetime2](7)  NULL,
    -- When the attempt was completed - NULL if still in progress
    [completed_date]  [datetime2](7)  NULL,
    -- Last question answered - used to resume incomplete attempts
    -- NULL at start, updated as student progresses
    [last_question_id] [int]          NULL,
    -- Final percentage score - calculated on completion
    -- decimal(5,2) supports scores like 87.50
    [score]           [decimal](5, 2) NULL,
    -- Total questions in this attempt (snapshot of quiz at attempt time)
    [total_questions] [tinyint]       NOT NULL,
    -- Running count of correct answers - defaults to 0
    [correct_answers] [tinyint]       NULL,
    -- Completion flag - 0=in progress, 1=completed
    -- Defaults to 0 (in progress) on creation
    [is_completed]    [bit]           NULL,
    -- Clustered PK - attempt lookups always by attempt_id
    CONSTRAINT pk_t_user_quiz_attempt_attempt_id PRIMARY KEY CLUSTERED ([attempt_id])
)
GO

-- Attempt start time defaults to current UTC time
ALTER TABLE [dbo].[t_user_quiz_attempt]
    ADD CONSTRAINT df_t_user_quiz_attempt_started_date DEFAULT (getutcdate()) FOR [started_date]
GO

-- Correct answer count starts at 0
ALTER TABLE [dbo].[t_user_quiz_attempt]
    ADD CONSTRAINT df_t_user_quiz_attempt_correct_answers DEFAULT ((0)) FOR [correct_answers]
GO

-- Attempts start as incomplete (0)
ALTER TABLE [dbo].[t_user_quiz_attempt]
    ADD CONSTRAINT df_t_user_quiz_attempt_is_completed DEFAULT ((0)) FOR [is_completed]
GO

-- last_question_id must reference a valid question
-- NULL allowed - no question answered yet at start of attempt
ALTER TABLE [dbo].[t_user_quiz_attempt]
    WITH CHECK ADD CONSTRAINT fk_t_user_quiz_attempt_t_question_last_question_id_question_id
    FOREIGN KEY ([last_question_id]) REFERENCES [dbo].[t_question] ([question_id])
GO

-- Attempt must reference a valid quiz
ALTER TABLE [dbo].[t_user_quiz_attempt]
    WITH CHECK ADD CONSTRAINT fk_t_user_quiz_attempt_t_quiz_quiz_id
    FOREIGN KEY ([quiz_id]) REFERENCES [dbo].[t_quiz] ([quiz_id])
GO

-- Attempt must belong to a valid user
ALTER TABLE [dbo].[t_user_quiz_attempt]
    WITH CHECK ADD CONSTRAINT fk_t_user_quiz_attempt_t_user_user_id
    FOREIGN KEY ([user_id]) REFERENCES [dbo].[t_user] ([user_id])
GO

-- Supports filtering incomplete attempts for resume functionality
CREATE INDEX [ndx_user_quiz_attempt_is_completed]
    ON [dbo].[t_user_quiz_attempt] ([is_completed])
GO

-- Supports retrieving all attempts for a specific quiz
CREATE INDEX [ndx_user_quiz_attempt_quiz_id]
    ON [dbo].[t_user_quiz_attempt] ([quiz_id])
GO

-- Supports retrieving all attempts by a specific user
CREATE INDEX [ndx_user_quiz_attempt_user_id]
    ON [dbo].[t_user_quiz_attempt] ([user_id])
GO

-- =============================================================
-- t_user_answer
-- Records each individual answer submitted by a student during
-- a quiz attempt. user_answer_json stores the answer in a
-- flexible JSON format to accommodate different question types
-- (MultipleChoice, Matching, FillInBlank etc.) without
-- requiring separate tables per type.
-- =============================================================
CREATE TABLE [dbo].[t_user_answer](
    -- Auto-incrementing answer record identifier
    [user_answer_id]   [int]            IDENTITY(1,1) NOT NULL,
    -- Quiz attempt this answer belongs to
    [attempt_id]       [int]            NOT NULL,
    -- Question being answered
    [question_id]      [int]            NOT NULL,
    -- Student's answer stored as JSON to support all question types
    -- Format varies by question_type_id:
    --   MultipleChoice: {"selected_answer_id": 42}
    --   Matching:       {"pairs": [{"left":1,"right":3}, ...]}
    --   FillInBlank:    {"answer_text": "PROS"}
    [user_answer_json] [nvarchar](2048) NULL,
    -- Whether the submitted answer was correct
    -- NULL until answer is evaluated
    [is_correct]       [bit]            NULL,
    -- When the answer was submitted - defaults to current UTC time
    [answered_date]    [datetime2](7)   NULL,
    -- Clustered PK - answer lookups always by user_answer_id
    CONSTRAINT pk_t_user_answer_user_answer_id PRIMARY KEY CLUSTERED ([user_answer_id])
)
GO

-- Answer submission timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_user_answer]
    ADD CONSTRAINT df_t_user_answer_answered_date DEFAULT (getutcdate()) FOR [answered_date]
GO

-- Answer must reference a valid question
ALTER TABLE [dbo].[t_user_answer]
    WITH CHECK ADD CONSTRAINT fk_t_user_answer_t_question_question_id
    FOREIGN KEY ([question_id]) REFERENCES [dbo].[t_question] ([question_id])
GO

-- Answer must belong to a valid quiz attempt
ALTER TABLE [dbo].[t_user_answer]
    WITH CHECK ADD CONSTRAINT fk_t_user_answer_t_user_quiz_attempt_attempt_id
    FOREIGN KEY ([attempt_id]) REFERENCES [dbo].[t_user_quiz_attempt] ([attempt_id])
GO

-- Supports retrieving all answers for a specific attempt
-- Used when displaying attempt review and calculating scores
CREATE INDEX ndx_t_user_answer_attempt_id
    ON [dbo].[t_user_answer] ([attempt_id])
GO

-- =============================================================
-- t_answer
-- Stores the correct/incorrect answer options for each question.
-- Multiple rows per question - one per answer choice.
-- Supports matching questions via match_pair_id and match_side:
--   match_pair_id groups left/right pairs together
--   match_side indicates which side ('L' or 'R') of the pair
-- =============================================================
CREATE TABLE [dbo].[t_answer](
    -- Auto-incrementing answer option identifier
    [answer_id]         [int]            IDENTITY(1,1) NOT NULL,
    -- Question this answer option belongs to
    [question_id]       [int]            NOT NULL,
    -- Answer option text shown to student
    -- nvarchar supports Unicode for code samples
    [answer_text]       [nvarchar](500)  NOT NULL,
    -- Optional path to answer option image
    -- NULL if answer has no associated image
    [answer_image_path] [varchar](500)   NULL,
    -- Whether this answer option is correct - defaults to 0 (incorrect)
    -- For matching questions, all options have is_correct = 1
    -- when correctly paired via match_pair_id
    [is_correct]        [bit]            NULL,
    -- Sort order of answer options within the question
    -- Defaults to 0
    [answer_order]      [tinyint]        NULL,
    -- Groups matching question pairs together
    -- NULL for non-matching question types
    -- Same match_pair_id on left and right items means they are a pair
    [match_pair_id]     [tinyint]        NULL,
    -- Side of matching pair: 'L' = left column, 'R' = right column
    -- NULL for non-matching question types
    [match_side]        [char](1)        NULL,
    -- Visual display order independent of answer_order
    [display_order]     [tinyint]        NULL,
    -- Clustered PK - answer lookups always by answer_id
    CONSTRAINT pk_t_answer_answer_id PRIMARY KEY CLUSTERED ([answer_id])
)
GO

-- Answer options default to incorrect (0) - correct answers explicitly set
ALTER TABLE [dbo].[t_answer]
    ADD CONSTRAINT df_t_answer_is_correct DEFAULT ((0)) FOR [is_correct]
GO

-- Answer options default to sort position 0
ALTER TABLE [dbo].[t_answer]
    ADD CONSTRAINT df_t_answer_answer_order DEFAULT ((0)) FOR [answer_order]
GO

-- Each answer option must belong to a valid question
ALTER TABLE [dbo].[t_answer]
    WITH CHECK ADD CONSTRAINT fk_t_answer_t_question_question_id
    FOREIGN KEY ([question_id]) REFERENCES [dbo].[t_question] ([question_id])
GO

-- Supports retrieving all answer options for a specific question
-- Used when rendering quiz questions in mobile app
CREATE INDEX [ndx_t_answer_question_id]
    ON [dbo].[t_answer] ([question_id])
GO

-- =============================================================
-- t_user_lesson_read
-- Tracks which lessons each user has read on the website.
-- Composite PK on (user_id, lesson_id) enforces one read
-- record per user per lesson. read_date records the most
-- recent read timestamp - updated on re-reads.
-- Used to show reading progress in the student dashboard.
-- =============================================================
CREATE TABLE [dbo].[t_user_lesson_read](
    -- User who read the lesson
    [user_id]   [int]          NOT NULL,
    -- Lesson that was read
    [lesson_id] [smallint]     NOT NULL,
    -- When the lesson was (most recently) read in UTC
    [read_date] [datetime2](7) NULL,
    -- Composite PK - one read record per user per lesson
    CONSTRAINT pk_t_user_lesson_read_lesson_id PRIMARY KEY CLUSTERED ([user_id], [lesson_id])
)
GO

-- Read timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_user_lesson_read]
    ADD CONSTRAINT df_t_user_lesson_read_read_date DEFAULT (getutcdate()) FOR [read_date]
GO

-- Must reference a valid lesson
ALTER TABLE [dbo].[t_user_lesson_read]
    WITH CHECK ADD CONSTRAINT fk_t_user_lesson_read_t_lesson_lesson_id
    FOREIGN KEY ([lesson_id]) REFERENCES [dbo].[t_lesson] ([lesson_id])
GO

-- Must reference a valid user
ALTER TABLE [dbo].[t_user_lesson_read]
    WITH CHECK ADD CONSTRAINT fk_t_user_lesson_read_t_user_user_id
    FOREIGN KEY ([user_id]) REFERENCES [dbo].[t_user] ([user_id])
GO

-- =============================================================
-- t_user_topic_read
-- Tracks reading progress at the topic (section) level within
-- lessons. More granular than t_user_lesson_read - allows the
-- mobile app to resume a lesson at the last unread topic.
-- Composite PK on (user_id, topic_id) enforces one record
-- per user per topic.
-- =============================================================
CREATE TABLE [dbo].[t_user_topic_read](
    -- User who read the topic
    [user_id]  [int]          NOT NULL,
    -- Topic (section) that was read
    [topic_id] [int]          NOT NULL,
    -- When the topic was (most recently) read in UTC
    [read_date] [datetime2](7) NULL,
    -- Composite PK - one read record per user per topic
    CONSTRAINT pk_t_user_topic_read_user_id_topic_id PRIMARY KEY CLUSTERED ([user_id], [topic_id])
)
GO

-- Read timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_user_topic_read]
    ADD CONSTRAINT df_t_user_topic_read_read_date DEFAULT (getutcdate()) FOR [read_date]
GO

-- Must reference a valid user
ALTER TABLE [dbo].[t_user_topic_read]
    WITH CHECK ADD CONSTRAINT fk_t_user_topic_read_t_user_user_id
    FOREIGN KEY ([user_id]) REFERENCES [dbo].[t_user] ([user_id])
GO

-- Must reference a valid topic
ALTER TABLE [dbo].[t_user_topic_read]
    WITH CHECK ADD CONSTRAINT fk_t_user_topic_read_t_topic_topic_id
    FOREIGN KEY ([topic_id]) REFERENCES [dbo].[t_topic] ([topic_id])
GO

-- =============================================================
-- t_account_deletion_requests
-- Manages secure account deletion workflow. When a user
-- requests account deletion, a token is generated and emailed
-- to them. The deletion only proceeds when the user confirms
-- via the token link within the expiry window.
-- user_id is nullable to handle cases where the user record
-- may already be deactivated before deletion is confirmed.
-- =============================================================
CREATE TABLE [dbo].[t_account_deletion_requests](
    -- Auto-incrementing request identifier
    [id]         [int]            IDENTITY(1,1) NOT NULL,
    -- User requesting deletion - nullable in case account
    -- is deactivated before deletion request is confirmed
    [user_id]    [int]            NULL,
    -- Email address of the requesting user
    -- Stored separately from user_id for audit trail
    [email]      [nvarchar](254)  NOT NULL,
    -- Secure random token sent to user's email for confirmation
    -- nvarchar(128) accommodates GUID or cryptographic token
    [token]      [nvarchar](128)  NOT NULL,
    -- When the deletion request was created in UTC
    [created_at] [datetime2](7)   NOT NULL,
    -- When the confirmation token expires in UTC
    -- Requests not confirmed before this time are abandoned
    [expires_at] [datetime2](7)   NOT NULL,
    -- When the token was used to confirm deletion
    -- NULL until deletion is confirmed
    [used_at]    [datetime2](7)   NULL,
    -- IP address of the client that made the deletion request
    -- Stored for security auditing purposes
    [ip_address] [nvarchar](64)   NULL,
    -- Clustered PK - request lookups always by id
    CONSTRAINT pk_t_account_deletion_requests_id PRIMARY KEY CLUSTERED ([id]),
    -- Tokens must be unique to prevent collision attacks
    CONSTRAINT ndxu_t_account_deletion_requests_token UNIQUE NONCLUSTERED ([token])
)
GO

-- Request creation timestamp defaults to current UTC time
ALTER TABLE [dbo].[t_account_deletion_requests]
    ADD CONSTRAINT df_t_account_deletion_requests_created_at DEFAULT (getutcdate()) FOR [created_at]
GO

-- Request must reference a valid user (nullable FK)
ALTER TABLE [dbo].[t_account_deletion_requests]
    WITH CHECK ADD CONSTRAINT fk_t_account_deletion_requests_t_user_user_id
    FOREIGN KEY ([user_id]) REFERENCES [dbo].[t_user] ([user_id])
GO

-- Supports looking up pending deletion requests by email
-- Used to prevent duplicate deletion requests from same email
CREATE INDEX [ndx_t_account_deletion_requests_email]
    ON [dbo].[t_account_deletion_requests] ([email])
GO

-- END OF SCRIPT
