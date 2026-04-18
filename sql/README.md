# VexTrainer Database — SQL Scripts

This folder contains all SQL scripts required to set up and maintain
the VexTrainer database on SQL Server 2019+.

---

## Folder Structure

```
sql/
-- 01-create-database.sql       # Creates the VexTrainer01 database
-- 02-create-login.sql          # Creates logins, users, and roles
-- 03-create-tables.sql         # Creates all tables, indexes, and constraints
-- sp_*.sql                     # Stored procedures (one file per procedure)

util/
-- Deploy-StoredProcedures.ps1  # Script to compile all stored procedures
-- stored-procedures.txt        # Ordered list of stored procedures to compile
```

---

## Setup Order

Scripts must be run in the following order. Steps 1–3 are run manually
via SSMS or sqlcmd. Step 4 uses the provided deployment script.

### Step 1 — Create the Database
Run as a SQL Server **sysadmin** (e.g. `sa` or Windows admin login):
```
sqlcmd -S <server> -E -i sql\01-create-database.sql
```
Or open in SSMS and execute.

> Update the `FILENAME` paths in `01-create-database.sql` to match
> your server's data and log file locations before running.

---

### Step 2 — Create Logins and Roles
Run as a SQL Server **sysadmin**:
```
sqlcmd -S <server> -E -i sql\02-create-login.sql
```

> The script contains placeholder passwords (`INSERT_STRONG_PASSWORD_HERE`).
> Replace both occurrences with strong, unique passwords before running.
> Use different passwords for `vextrainer01_dbo` and `vextrainer_teachers`.
> Never commit real passwords to this repository.

This creates:

| Login | Role | Purpose |
|---|---|---|
| `vextrainer01_dbo` | `db_owner` | DDL account — used to create/alter database objects |
| `vextrainer_teachers` | `staff` | Application runtime account — executes stored procedures only |

---

### Step 3 — Create Tables
Run using the **`vextrainer01_dbo`** login:
```
sqlcmd -S <server> -U vextrainer_dbo -P <password> -d VexTrainer01 -i sql\03-create-tables.sql
```

---

### Step 4 — Deploy Stored Procedures
Use the provided PowerShell script to compile all stored procedures
and automatically grant `EXECUTE` permission to the `staff` role.

Run from the repository root:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1
```

You will be prompted for:
```
Server name   : localhost          (or server\instance)
Login name    : vextrainer01_dbo     ← must use this login
Password      : ****               (masked)
Database name : VexTrainer01
```

> You must use the `vextrainer01_dbo` login for this step.
> The `vextrainer_teachers` login cannot create or alter stored procedures.

See [Stored Procedure Deployment](#stored-procedure-deployment) below
for full details on the deployment script.

---

## Stored Procedure Deployment

### Prerequisites

**sqlcmd** is required. It is included with:
- SQL Server (any edition)
- SQL Server Management Studio (SSMS)
- SQL Server Command Line Tools (standalone)

Verify it is available:
```
sqlcmd -?
```

If not installed, download the standalone tools:
https://aka.ms/sqlcmdinstall

**Alternatively — SqlServer PowerShell Module**
If `sqlcmd` is not available, install the PowerShell module:
```powershell
Install-Module SqlServer -Scope CurrentUser
```
Note: The deployment script uses `sqlcmd` by default. If using the
PowerShell module instead, run the SQL files manually via SSMS.

---

### Running the Script

#### Basic usage (prompted for all connection details):
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1
```

#### With parameters (skips prompts for server, login, database):
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1 `
    -serverName "localhost" `
    -loginName "vextrainer01_dbo" `
    -databaseName "VexTrainer01"
```

> Password is **always** prompted interactively regardless of other
> parameters — it is never accepted on the command line to prevent
> it appearing in shell history.

#### Using a custom list file:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\util\Deploy-StoredProcedures.ps1 `
    -listFile "my-procs.txt"
```

---

### What the Script Does

For each stored procedure listed in `stored-procedures.txt`:

1. Locates the `.sql` file in the `sql\` folder
2. Compiles it using `sqlcmd`
3. If compilation succeeds, automatically runs:
   ```sql
   GRANT EXECUTE ON [dbo].[proc_name] TO [staff];
   ```
4. If compilation fails, logs the error and continues with the next file
5. Prints a full summary at the end showing successes and failures

---

### stored-procedures.txt Format

One filename per line. Blank lines and lines starting with `#` are ignored.
Procedures are compiled in the order listed.

```
# Module content procedures
sp_GetModules.sql
sp_GetLessons.sql
sp_GetTopics.sql

# Quiz procedures
sp_GetQuiz.sql
sp_GetQuestions.sql
sp_GetAnswers.sql

# User progress procedures
sp_SaveLessonRead.sql
sp_SaveQuizAttempt.sql
```

---

### Fixing Failures

If any procedures fail to compile, the summary will show:
```
  Failed compilations:
    [FAIL] sp_GetQuizResults.sql
           Msg 208, Level 16 - Invalid object name ...
```

Fix the SQL file, then either:
- Re-run the full script (already-compiled procedures will simply recompile), or
- Temporarily edit `stored-procedures.txt` to list only the failed files

---

## Application Connection String

The application (`vextrainer-api` and `vextrainer-web`) must connect
using the **`vextrainer_teachers`** login — never `vextrainer_dbo`.

Example connection string format (values in `appsettings.Development.json`):
```
Server=<server>;Database=VexTrainer01;User Id=vextrainer_teachers;Password=<password>;
```

> The `vextrainer_dbo` login is for database administration only.
> Its credentials should never appear in any application config file.

---

## Security Model

| | `vextrainer_dbo` | `vextrainer_teachers` |
|---|---|---|
| **Role** | `db_owner` | `staff` |
| **Create/alter tables** | Y | N |
| **Create/alter procedures** | Y | N |
| **Execute procedures** | Y | Y |
| **Direct table SELECT** | Y | N |
| **Used by application** | N | Y |
| **Used for deployments** | Y | N |
