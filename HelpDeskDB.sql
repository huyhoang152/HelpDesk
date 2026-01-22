/* =========================================================
   HelpDeskDB - SQL Server (Rerunnable Script)
   - Roles / Users / Tickets / Comments / Attachments / History
   - SLAConfigs / Ratings / AuditLogs
   - Optimized for DB-First EF Core
   ========================================================= */

-- 0) Create DB if not exists
IF DB_ID(N'HelpDeskDB') IS NULL
BEGIN
    CREATE DATABASE HelpDeskDB;
END
GO

USE HelpDeskDB;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   1) DROP TABLES (FK-safe order) - so script is rerunnable
   ========================================================= */
IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NOT NULL DROP TABLE dbo.AuditLogs;
IF OBJECT_ID(N'dbo.TicketRatings', N'U') IS NOT NULL DROP TABLE dbo.TicketRatings;
IF OBJECT_ID(N'dbo.SLAConfigs', N'U') IS NOT NULL DROP TABLE dbo.SLAConfigs;

IF OBJECT_ID(N'dbo.TicketHistory', N'U') IS NOT NULL DROP TABLE dbo.TicketHistory;
IF OBJECT_ID(N'dbo.TicketAttachments', N'U') IS NOT NULL DROP TABLE dbo.TicketAttachments;
IF OBJECT_ID(N'dbo.TicketComments', N'U') IS NOT NULL DROP TABLE dbo.TicketComments;
IF OBJECT_ID(N'dbo.Tickets', N'U') IS NOT NULL DROP TABLE dbo.Tickets;

IF OBJECT_ID(N'dbo.TicketStatus', N'U') IS NOT NULL DROP TABLE dbo.TicketStatus;
IF OBJECT_ID(N'dbo.TicketPriorities', N'U') IS NOT NULL DROP TABLE dbo.TicketPriorities;
IF OBJECT_ID(N'dbo.TicketCategories', N'U') IS NOT NULL DROP TABLE dbo.TicketCategories;

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL DROP TABLE dbo.Users;
IF OBJECT_ID(N'dbo.Roles', N'U') IS NOT NULL DROP TABLE dbo.Roles;
GO

/* =========================================================
   2) LOOKUP TABLES
   ========================================================= */

-- Roles
CREATE TABLE dbo.Roles (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
    Name NVARCHAR(20) NOT NULL CONSTRAINT UQ_Roles_Name UNIQUE
);
GO

INSERT INTO dbo.Roles (Name)
VALUES (N'EndUser'), (N'Agent'), (N'Admin');
GO

-- Ticket Categories
CREATE TABLE dbo.TicketCategories (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketCategories PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL CONSTRAINT UQ_TicketCategories_Name UNIQUE,
    Description NVARCHAR(255) NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_TicketCategories_IsActive DEFAULT (1),
    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_TicketCategories_CreatedAt DEFAULT (SYSUTCDATETIME())
);
GO

INSERT INTO dbo.TicketCategories (Name)
VALUES (N'IT Support'), (N'Phần mềm'), (N'Phần cứng'), (N'Khác');
GO

-- Ticket Priorities
CREATE TABLE dbo.TicketPriorities (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketPriorities PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL CONSTRAINT UQ_TicketPriorities_Name UNIQUE,
    Level INT NOT NULL,
    CONSTRAINT CK_TicketPriorities_Level CHECK (Level BETWEEN 1 AND 10)
);
GO

INSERT INTO dbo.TicketPriorities (Name, Level)
VALUES 
(N'Low', 1),
(N'Medium', 2),
(N'High', 3),
(N'Critical', 4);
GO

-- Ticket Status (fixed IDs 0..6)
CREATE TABLE dbo.TicketStatus (
    Id TINYINT NOT NULL CONSTRAINT PK_TicketStatus PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL CONSTRAINT UQ_TicketStatus_Name UNIQUE
);
GO

INSERT INTO dbo.TicketStatus (Id, Name)
VALUES
(0, N'New'),
(1, N'Assigned'),
(2, N'In Progress'),
(3, N'Pending User'),
(4, N'Resolved'),
(5, N'Closed'),
(6, N'Reopened');
GO

/* =========================================================
   3) USERS
   ========================================================= */
CREATE TABLE dbo.Users (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL CONSTRAINT UQ_Users_Username UNIQUE,
    Email NVARCHAR(100) NULL CONSTRAINT UQ_Users_Email UNIQUE,
    PasswordHash NVARCHAR(500) NOT NULL,
    RoleId INT NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Users_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Users_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(Id)
);
GO

CREATE INDEX IX_Users_RoleId ON dbo.Users(RoleId);
GO

/* =========================================================
   4) TICKETS
   ========================================================= */

-- Sequence for TicketCode like HD-000001
IF OBJECT_ID(N'dbo.TicketCodeSeq', N'SO') IS NOT NULL DROP SEQUENCE dbo.TicketCodeSeq;
GO
CREATE SEQUENCE dbo.TicketCodeSeq AS BIGINT START WITH 1 INCREMENT BY 1;
GO

CREATE TABLE dbo.Tickets (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Tickets PRIMARY KEY,

    TicketCode NVARCHAR(20) NOT NULL CONSTRAINT DF_Tickets_TicketCode
        DEFAULT (CONCAT(N'HD-', RIGHT(CONCAT(N'000000', CAST(NEXT VALUE FOR dbo.TicketCodeSeq AS NVARCHAR(20))), 6))),
    Title NVARCHAR(255) NOT NULL,
    Description NVARCHAR(MAX) NULL,

    CategoryId INT NOT NULL,
    PriorityId INT NOT NULL,
    StatusId TINYINT NOT NULL CONSTRAINT DF_Tickets_StatusId DEFAULT (0),

    CreatedBy INT NOT NULL,     -- EndUser (enforce by app)
    AssignedTo INT NULL,        -- Agent   (enforce by app)

    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Tickets_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Tickets_UpdatedAt DEFAULT (SYSUTCDATETIME()),

    -- SLA tracking fields (optional but recommended)
    FirstResponseAt DATETIME2(3) NULL,
    ResponseDueAt DATETIME2(3) NULL,
    ResolveDueAt DATETIME2(3) NULL,
    SlaPausedMinutes INT NOT NULL CONSTRAINT DF_Tickets_SlaPausedMinutes DEFAULT (0),
    IsSlaBreached BIT NOT NULL CONSTRAINT DF_Tickets_IsSlaBreached DEFAULT (0),

    -- Business dates
    DueAt DATETIME2(3) NULL,
    ResolvedAt DATETIME2(3) NULL,
    ClosedAt DATETIME2(3) NULL,

    RowVer ROWVERSION NOT NULL,

    CONSTRAINT UQ_Tickets_TicketCode UNIQUE (TicketCode),

    CONSTRAINT FK_Tickets_Category FOREIGN KEY (CategoryId) REFERENCES dbo.TicketCategories(Id),
    CONSTRAINT FK_Tickets_Priority FOREIGN KEY (PriorityId) REFERENCES dbo.TicketPriorities(Id),
    CONSTRAINT FK_Tickets_Status FOREIGN KEY (StatusId) REFERENCES dbo.TicketStatus(Id),
    CONSTRAINT FK_Tickets_CreatedBy FOREIGN KEY (CreatedBy) REFERENCES dbo.Users(Id),
    CONSTRAINT FK_Tickets_AssignedTo FOREIGN KEY (AssignedTo) REFERENCES dbo.Users(Id),

    CONSTRAINT CK_Tickets_ResolvedAfterCreated CHECK (ResolvedAt IS NULL OR ResolvedAt >= CreatedAt),
    CONSTRAINT CK_Tickets_ClosedAfterCreated CHECK (ClosedAt IS NULL OR ClosedAt >= CreatedAt),
    CONSTRAINT CK_Tickets_FirstResponseAfterCreated CHECK (FirstResponseAt IS NULL OR FirstResponseAt >= CreatedAt)
);
GO

-- Helpful indexes
CREATE INDEX IX_Tickets_Status_ResolveDueAt ON dbo.Tickets(StatusId, ResolveDueAt);
CREATE INDEX IX_Tickets_AssignedTo_StatusId ON dbo.Tickets(AssignedTo, StatusId);
CREATE INDEX IX_Tickets_CreatedBy_CreatedAt ON dbo.Tickets(CreatedBy, CreatedAt DESC);
CREATE INDEX IX_Tickets_Category_Priority ON dbo.Tickets(CategoryId, PriorityId);
GO

/* =========================================================
   5) COMMENTS
   ========================================================= */
CREATE TABLE dbo.TicketComments (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketComments PRIMARY KEY,
    TicketId INT NOT NULL,
    Content NVARCHAR(MAX) NOT NULL,
    CreatedBy INT NOT NULL,
    IsInternal BIT NOT NULL CONSTRAINT DF_TicketComments_IsInternal DEFAULT (0),
    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_TicketComments_CreatedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT FK_Comments_Tickets FOREIGN KEY (TicketId) REFERENCES dbo.Tickets(Id),
    CONSTRAINT FK_Comments_Users FOREIGN KEY (CreatedBy) REFERENCES dbo.Users(Id)
);
GO
CREATE INDEX IX_TicketComments_TicketId_CreatedAt ON dbo.TicketComments(TicketId, CreatedAt);
GO

/* =========================================================
   6) ATTACHMENTS
   ========================================================= */
CREATE TABLE dbo.TicketAttachments (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketAttachments PRIMARY KEY,
    TicketId INT NOT NULL,
    FileName NVARCHAR(255) NOT NULL,
    FilePath NVARCHAR(500) NOT NULL,
    ContentType NVARCHAR(100) NULL,
    SizeBytes BIGINT NOT NULL CONSTRAINT DF_TicketAttachments_SizeBytes DEFAULT (0),
    UploadedBy INT NOT NULL,
    UploadedAt DATETIME2(3) NOT NULL CONSTRAINT DF_TicketAttachments_UploadedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT FK_Attachments_Tickets FOREIGN KEY (TicketId) REFERENCES dbo.Tickets(Id),
    CONSTRAINT FK_Attachments_Users FOREIGN KEY (UploadedBy) REFERENCES dbo.Users(Id),
    CONSTRAINT CK_TicketAttachments_SizeBytes CHECK (SizeBytes >= 0)
);
GO
CREATE INDEX IX_TicketAttachments_TicketId_UploadedAt ON dbo.TicketAttachments(TicketId, UploadedAt);
GO

/* =========================================================
   7) TICKET HISTORY
   - status + other changes logging
   ========================================================= */
CREATE TABLE dbo.TicketHistory (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketHistory PRIMARY KEY,
    TicketId INT NOT NULL,

    Action NVARCHAR(100) NOT NULL,     -- e.g. StatusChanged, Assigned, PriorityChanged...
    FieldName NVARCHAR(100) NULL,      -- e.g. StatusId, AssignedTo...
    OldValue NVARCHAR(MAX) NULL,
    NewValue NVARCHAR(MAX) NULL,

    OldStatus TINYINT NULL,
    NewStatus TINYINT NULL,

    ActionBy INT NOT NULL,
    ActionAt DATETIME2(3) NOT NULL CONSTRAINT DF_TicketHistory_ActionAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT FK_History_Tickets FOREIGN KEY (TicketId) REFERENCES dbo.Tickets(Id),
    CONSTRAINT FK_History_Users FOREIGN KEY (ActionBy) REFERENCES dbo.Users(Id),
    CONSTRAINT FK_History_OldStatus FOREIGN KEY (OldStatus) REFERENCES dbo.TicketStatus(Id),
    CONSTRAINT FK_History_NewStatus FOREIGN KEY (NewStatus) REFERENCES dbo.TicketStatus(Id)
);
GO
CREATE INDEX IX_TicketHistory_TicketId_ActionAt ON dbo.TicketHistory(TicketId, ActionAt);
GO

/* =========================================================
   8) SLA CONFIGS
   ========================================================= */
CREATE TABLE dbo.SLAConfigs (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SLAConfigs PRIMARY KEY,
    PriorityId INT NOT NULL,
    ResponseMinutes INT NOT NULL,
    ResolveMinutes INT NOT NULL,

    CONSTRAINT FK_SLA_Priority FOREIGN KEY (PriorityId) REFERENCES dbo.TicketPriorities(Id),
    CONSTRAINT UQ_SLAConfigs_Priority UNIQUE (PriorityId),
    CONSTRAINT CK_SLA_ResponseMinutes CHECK (ResponseMinutes > 0),
    CONSTRAINT CK_SLA_ResolveMinutes CHECK (ResolveMinutes > 0)
);
GO

INSERT INTO dbo.SLAConfigs (PriorityId, ResponseMinutes, ResolveMinutes)
VALUES
((SELECT Id FROM dbo.TicketPriorities WHERE Name = N'Low'),      480, 4320),
((SELECT Id FROM dbo.TicketPriorities WHERE Name = N'Medium'),   240, 2880),
((SELECT Id FROM dbo.TicketPriorities WHERE Name = N'High'),      60,  480),
((SELECT Id FROM dbo.TicketPriorities WHERE Name = N'Critical'),  15,  240);
GO

/* =========================================================
   9) RATINGS
   ========================================================= */
CREATE TABLE dbo.TicketRatings (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TicketRatings PRIMARY KEY,
    TicketId INT NOT NULL,
    RatedBy INT NOT NULL,
    Rating TINYINT NOT NULL,
    Comment NVARCHAR(255) NULL,
    RatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_TicketRatings_RatedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT UQ_TicketRatings_Ticket UNIQUE (TicketId),
    CONSTRAINT FK_Ratings_Tickets FOREIGN KEY (TicketId) REFERENCES dbo.Tickets(Id),
    CONSTRAINT FK_Ratings_Users FOREIGN KEY (RatedBy) REFERENCES dbo.Users(Id),
    CONSTRAINT CK_TicketRatings_Rating CHECK (Rating BETWEEN 1 AND 5)
);
GO

/* =========================================================
   10) AUDIT LOGS
   ========================================================= */
CREATE TABLE dbo.AuditLogs (
    Id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLogs PRIMARY KEY,
    Action NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    PerformedBy INT NULL,
    CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_AuditLogs_CreatedAt DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT FK_Audit_Users FOREIGN KEY (PerformedBy) REFERENCES dbo.Users(Id)
);
GO
CREATE INDEX IX_AuditLogs_CreatedAt ON dbo.AuditLogs(CreatedAt DESC);
CREATE INDEX IX_AuditLogs_PerformedBy_CreatedAt ON dbo.AuditLogs(PerformedBy, CreatedAt DESC);
GO

/* =========================================================
   11) SEED USERS (SAFE: RoleId by name, not fixed numbers)
   ========================================================= */
DECLARE @RoleAdmin INT  = (SELECT Id FROM dbo.Roles WHERE Name = N'Admin');
DECLARE @RoleAgent INT  = (SELECT Id FROM dbo.Roles WHERE Name = N'Agent');
DECLARE @RoleEnd   INT  = (SELECT Id FROM dbo.Roles WHERE Name = N'EndUser');

INSERT INTO dbo.Users (Username, Email, PasswordHash, RoleId)
VALUES
(N'admin',  N'admin@helpdesk.com', N'HASHED_PASSWORD', @RoleAdmin),
(N'agent01',N'agent@helpdesk.com', N'HASHED_PASSWORD', @RoleAgent),
(N'user01', N'user@helpdesk.com',  N'HASHED_PASSWORD', @RoleEnd);
GO

PRINT 'HelpDeskDB schema created successfully.';
GO
