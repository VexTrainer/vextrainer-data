# VexTrainer Data Layer

This repository is part of the [VexTrainer](https://vextrainer.com) platform —
a free, community-driven learning platform that teaches VEX Robotics Competition
(VRC) programming to students and teams worldwide.

VexTrainer provides structured lessons and quizzes covering the VEX PROS C++
programming environment — from hardware basics and motor control through to
autonomous driving and PID control. Lessons are readable on the web, and both
lessons and quizzes are available on Android and iOS mobile apps.

The platform is free to use. If you find it helpful, donations are welcome to
support farmers in need. Community contributions to the curriculum are also
welcome — see [vextrainer-content](https://github.com/VexTrainer/vextrainer-content)
for details.

---

## About This Repository

`vextrainer-data` is the **shared data access layer** for the VexTrainer platform.
It is a .NET class library that is referenced by both the API and web projects,
providing a single, consistent way to interact with the database.

It contains:
- **Data models** — C# classes representing database entities
- **Data services** — database access logic using Dapper
- **SQL scripts** — database creation, schema, and stored procedures

By keeping the data layer in a shared library, both the API and web projects
use identical models and queries — no duplication, no drift between platforms.

---

## Platform Repositories

The VexTrainer platform is made up of five repositories:

| Repository | Description |
|---|---|
| [vextrainer-data](https://github.com/VexTrainer/vextrainer-data) | You are here — shared data access layer |
| [vextrainer-api](https://github.com/VexTrainer/vextrainer-api) | ASP.NET Core REST API |
| [vextrainer-web](https://github.com/VexTrainer/vextrainer-web) | .NET website for reading lessons |
| [vextrainer-android](https://github.com/VexTrainer/vextrainer-android) | Android app for lessons and quizzes |
| [vextrainer-ios](https://github.com/VexTrainer/vextrainer-ios) | iOS app for lessons and quizzes |
| [vextrainer-content](https://github.com/VexTrainer/vextrainer-content) | Free VEX programming curriculum |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | C# / .NET 8 |
| Database | SQL Server 2019+ |
| Data access | Dapper |
| Authentication | JWT with refresh tokens |

---

## Repository Structure

```
vextrainer-data/
-- Models/          # C# classes representing database entities
-- Services/        # Data access services (Dapper queries)
-- sql/             # SQL scripts for database setup and stored procedures
----- 01-create-database.sql
----- 02-create-login.sql
----- 03-create-tables.sql
----- sp_*.sql    # Stored procedures (one file per procedure)
-- util/           # Developer utilities
-----  Deploy-StoredProcedures.ps1
-----  stored-procedures.txt
```

---

## Database Setup

Full database setup instructions are in [sql/README.md](sql/README.md).

At a high level:

1. Run `sql/01-create-database.sql` as sysadmin to create the database
2. Run `sql/02-create-login.sql` as sysadmin to create logins and roles
3. Run `sql/03-create-tables.sql` as `vextrainer01_dbo` to create all tables
4. Run `util/Deploy-StoredProcedures.ps1` to compile all stored procedures

> See [sql/README.md](sql/README.md) for full details including
> prerequisites, connection strings, and security model.

---

## Using This Library

This library is consumed by `vextrainer-api` and `vextrainer-web` as a
project reference. It is not published as a NuGet package.

To reference it in a .NET project, add a project reference in Visual Studio:

1. Right-click the consuming project => **Add** => **Project Reference**
2. Select `VexTrainer.Data`

Or in the `.csproj` file:
```xml
<ItemGroup>
  <ProjectReference Include="..\VexTrainer.Data\VexTrainer.Data.csproj" />
</ItemGroup>
```

---

## Contributing

Contributions to the curriculum content are warmly welcomed; see
[vextrainer-content](https://github.com/VexTrainer/vextrainer-content)
for how to add or correct lessons and quizzes.

For code contributions to this repository, please open an issue first
to discuss the change before submitting a pull request.

---

## License

Code in this repository is licensed under the [MIT License](LICENSE).

Curriculum content in [vextrainer-content](https://github.com/VexTrainer/vextrainer-content)
is licensed under [Creative Commons Attribution-NonCommercial 4.0](https://creativecommons.org/licenses/by-nc/4.0/).
