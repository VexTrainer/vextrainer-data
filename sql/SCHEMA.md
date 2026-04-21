# VexTrainer Database Schema

Entity-relationship diagram for the VexTrainer01 database.
For setup instructions see [README.md](README.md).

---

## ER Diagram

```mermaid
erDiagram

    %% -------------------------------------------------------
    %% REFERENCE TABLES
    %% -------------------------------------------------------

    t_role {
        tinyint role_id PK
        varchar role_name
    }

    t_question_type {
        tinyint question_type_id PK
        varchar question_type
    }

    %% -------------------------------------------------------
    %% USER AND SESSION
    %% -------------------------------------------------------

    t_user {
        int     user_id       PK
        varchar user_name
        varchar email
        varchar phone
        varchar password_hash
        datetime2 created_date
        datetime2 last_login_date
        bit     is_active
        tinyint role_id       FK
    }

    t_session {
        int       session_id       PK
        int       user_id          FK
        varchar   token
        varchar   refresh_token
        datetime2 created_date
        datetime2 expiry_date
        datetime2 last_renewed_date
        bit       is_active
        varchar   device_info
    }

    t_account_deletion_requests {
        int       id          PK
        int       user_id     FK
        nvarchar  email
        nvarchar  token
        datetime2 created_at
        datetime2 expires_at
        datetime2 used_at
        nvarchar  ip_address
    }

    %% -------------------------------------------------------
    %% CURRICULUM - CONTENT STRUCTURE
    %% -------------------------------------------------------

    t_module {
        smallint  module_id     PK
        varchar   module_name
        nvarchar  description
        tinyint   display_order
        bit       is_active
    }

    t_lesson {
        smallint  lesson_id     PK
        smallint  module_id     FK
        varchar   lesson_title
        smallint  display_order
        bit       is_active
        varchar   file_name     "computed"
    }

    t_topic {
        int       topic_id        PK
        smallint  lesson_id       FK
        varchar   topic_title
        tinyint   heading_level
        int       parent_topic_id FK
        smallint  display_order
        bit       is_active
    }

    %% -------------------------------------------------------
    %% QUIZ - CONTENT STRUCTURE
    %% -------------------------------------------------------

    t_category {
        smallint  category_id        PK
        smallint  parent_category_id FK
        varchar   category_name
        nvarchar  description
        tinyint   display_order
        bit       is_active
    }

    t_quiz {
        smallint  quiz_id         PK
        smallint  category_id     FK
        varchar   quiz_title
        tinyint   total_questions
        tinyint   display_order
        bit       is_active
        datetime2 created_date
    }

    t_question {
        int       question_id         PK
        smallint  quiz_id             FK
        tinyint   question_type_id    FK
        nvarchar  question_text
        varchar   question_image_path
        tinyint   question_order
        decimal   point_value
        nvarchar  explanation
        bit       is_active
        smallint  display_order
    }

    t_answer {
        int      answer_id         PK
        int      question_id       FK
        nvarchar answer_text
        varchar  answer_image_path
        bit      is_correct
        tinyint  answer_order
        tinyint  match_pair_id
        char     match_side
        tinyint  display_order
    }

    %% -------------------------------------------------------
    %% USER ACTIVITY - PROGRESS TRACKING
    %% -------------------------------------------------------

    t_user_quiz_attempt {
        int       attempt_id      PK
        int       user_id         FK
        smallint  quiz_id         FK
        datetime2 started_date
        datetime2 completed_date
        int       last_question_id FK
        decimal   score
        tinyint   total_questions
        tinyint   correct_answers
        bit       is_completed
    }

    t_user_answer {
        int       user_answer_id  PK
        int       attempt_id      FK
        int       question_id     FK
        nvarchar  user_answer_json
        bit       is_correct
        datetime2 answered_date
    }

    t_user_lesson_read {
        int       user_id    PK, FK
        smallint  lesson_id  PK, FK
        datetime2 read_date
    }

    t_user_topic_read {
        int       user_id   PK, FK
        int       topic_id  PK, FK
        datetime2 read_date
    }

    %% -------------------------------------------------------
    %% RELATIONSHIPS
    %% -------------------------------------------------------

    %% User and roles
    t_role                    ||--o{ t_user                    : "assigned to"
    t_user                    ||--o{ t_session                 : "has"
    t_user                    ||--o{ t_account_deletion_requests : "requests"

    %% Curriculum structure
    t_module                  ||--o{ t_lesson                  : "contains"
    t_lesson                  ||--o{ t_topic                   : "has"
    t_topic                   }o--o| t_topic                   : "parent of"

    %% Quiz structure
    t_category                }o--o| t_category                : "parent of"
    t_category                ||--o{ t_quiz                    : "contains"
    t_quiz                    ||--o{ t_question                : "has"
    t_question_type           ||--o{ t_question                : "types"
    t_question                ||--o{ t_answer                  : "has options"

    %% User progress - lessons
    t_user                    ||--o{ t_user_lesson_read        : "reads"
    t_lesson                  ||--o{ t_user_lesson_read        : "read by"
    t_user                    ||--o{ t_user_topic_read         : "reads"
    t_topic                   ||--o{ t_user_topic_read         : "read by"

    %% User progress - quizzes
    t_user                    ||--o{ t_user_quiz_attempt       : "attempts"
    t_quiz                    ||--o{ t_user_quiz_attempt       : "attempted in"
    t_question                }o--o| t_user_quiz_attempt       : "last answered in"
    t_user_quiz_attempt       ||--o{ t_user_answer             : "contains"
    t_question                ||--o{ t_user_answer             : "answered in"
```

---

## Key Design Notes

**Computed column — `t_lesson.file_name`**
Automatically generates the Markdown filename from `module_id` and `lesson_id`.
Format: `{module_id_5digits}-{lesson_id_5digits}.md`
Example: module 4, lesson 12 → `00004-00012.md`
Matches filenames in the [vextrainer-content](https://github.com/VexTrainer/vextrainer-content) repository.

**Self-referencing tables**
Both `t_category` and `t_topic` support hierarchical nesting via
`parent_category_id` and `parent_topic_id` respectively.
Top-level records have `NULL` in the parent column.

**Composite primary keys**
`t_user_lesson_read` and `t_user_topic_read` use composite PKs on
`(user_id, lesson_id)` and `(user_id, topic_id)` — enforcing one
progress record per user per lesson/topic at the database level.

**Matching questions**
`t_answer.match_pair_id` and `t_answer.match_side` support matching
question types. Answers sharing the same `match_pair_id` form a pair,
with `match_side = 'L'` for left column and `'R'` for right column.

**JSON answers**
`t_user_answer.user_answer_json` stores student answers in a flexible
JSON format to accommodate all question types without separate tables:
- Multiple choice: `{"selected_answer_id": 42}`
- Matching: `{"pairs": [{"left": 1, "right": 3}]}`
- Fill in blank: `{"answer_text": "PROS"}`

**Access control**
No direct table permissions are granted to any user or role.
All data access is exclusively through stored procedures,
with `EXECUTE` permission granted to the `staff` role only.
See [README.md](README.md) for the full security model.
