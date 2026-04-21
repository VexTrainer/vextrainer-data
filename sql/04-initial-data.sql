TRUNCATE TABLE dbo.t_role;
INSERT t_role (role_id, role_name) VALUES (1, 'Admin'), (2, 'Student');
go
TRUNCATE TABLE dbo.t_question_type;
INSERT dbo.[t_question_type] VALUES
   (1, 'Multiple choice - single answer'),
   (2, 'Multiple choice - multiple answers'),
   (3, 'Fill in the blank'),
   (4, 'True or False'),
   (5, 'Match pairs');
go

--END OF SCRIPT
