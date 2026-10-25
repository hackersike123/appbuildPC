@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"

echo [PCBUILD] Checking local prerequisites...
if not exist "%ROOT%backend\.env" goto missing_env
if not exist "%ROOT%backend\node_modules\mssql" goto missing_node_modules
where node >nul 2>&1
if errorlevel 1 goto missing_node
where powershell >nul 2>&1
if errorlevel 1 goto missing_powershell

echo [PCBUILD] Checking remote SQL Server connection...
pushd "%ROOT%backend"
node --env-file=.env -e "const sql=require('mssql'); sql.connect({server:process.env.MSSQL_SERVER,port:Number(process.env.MSSQL_PORT),user:process.env.MSSQL_USER,password:process.env.MSSQL_PASSWORD,database:process.env.MSSQL_DATABASE,connectionTimeout:Number(process.env.MSSQL_CONNECTION_TIMEOUT||10000),requestTimeout:Number(process.env.MSSQL_REQUEST_TIMEOUT||10000),options:{encrypt:process.env.MSSQL_ENCRYPT==='true',trustServerCertificate:process.env.MSSQL_TRUST_SERVER_CERTIFICATE==='true'}}).then(async pool=>{console.log('SQL Server connected');await pool.close()}).catch(error=>{console.error('SQL Server connection failed:',error.message);process.exit(1)})"
if errorlevel 1 goto sql_failed
popd

call :check_api
if errorlevel 2 goto api_port_conflict
if errorlevel 1 goto start_api
echo [PCBUILD] Reusing the healthy API on port 3000.
goto ready

:start_api
echo [PCBUILD] Starting Node.js API on port 3000...
start "PCBUILD API - 3000" /D "%ROOT%backend" "%ComSpec%" /k "npm start"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$deadline=(Get-Date).AddSeconds(90); do { try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health' -TimeoutSec 3; if ($r.ok -and $r.service -eq 'pcbuild-local-api') { exit 0 } } catch {}; Start-Sleep -Seconds 2 } while ((Get-Date) -lt $deadline); exit 1"
if errorlevel 1 goto api_start_failed

:ready
echo.
echo [PCBUILD] Backend is ready.
echo   API:      http://localhost:3000/health
echo   API docs: http://localhost:3000/docs
echo   AI provider: LM Studio (see backend\.env)
echo.
echo The API log is in its console window. Press Ctrl+C there to stop the API.
exit /b 0

:check_api
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health' -TimeoutSec 2; if ($r.ok -and $r.service -eq 'pcbuild-local-api') { exit 0 }; exit 2 } catch { if (Get-NetTCPConnection -State Listen -LocalPort 3000 -ErrorAction SilentlyContinue) { exit 2 }; exit 1 }" >nul 2>&1
exit /b %errorlevel%

:missing_env
echo [ERROR] Missing backend\.env. Copy backend\.env.example and configure SQL credentials.
goto failed

:missing_node_modules
echo [ERROR] Backend dependencies are missing. Run "npm install" in backend\ first.
goto failed

:missing_node
echo [ERROR] Node.js is missing from PATH.
goto failed

:missing_powershell
echo [ERROR] Windows PowerShell is required by this launcher.
goto failed

:sql_failed
popd
echo [ERROR] Cannot connect to SQL Server. Check backend\.env and remote SQL availability.
goto failed

:api_port_conflict
echo [ERROR] Port 3000 is occupied by a service that is not the PCBUILD API.
goto failed

:api_start_failed
echo [ERROR] Backend API did not become healthy within 90 seconds. Check its console window.
goto failed

:failed
echo.
pause
exit /b 1
