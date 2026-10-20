-- PCBUILD LOCAL SQL Server bootstrap.
-- The Node.js API stores its complete domain document in this table so the
-- existing API contract remains unchanged during the SQL Server migration.
IF OBJECT_ID(N'dbo.pcbuild_app_state', N'U') IS NULL
BEGIN
  CREATE TABLE dbo.pcbuild_app_state (
    state_id INT NOT NULL CONSTRAINT PK_pcbuild_app_state PRIMARY KEY,
    payload NVARCHAR(MAX) NOT NULL,
    updated_at DATETIME2(3) NOT NULL CONSTRAINT DF_pcbuild_app_state_updated_at DEFAULT SYSUTCDATETIME()
  );
END;
GO
