@echo off
rem Deploys the Cloud Functions (generateStudyPlan = Claude AI, emailStudyPlan = plan emails) to Firebase.
rem Needs: project on the Blaze plan, your Anthropic API key, and a Gmail address + app password.
rem Each is asked once and stored as a Firebase secret (Google Secret Manager), never in the app.
cd /d "%~dp0"
echo.
echo === 1/4  Installing function packages ===
call npm --prefix functions install --no-audit --no-fund || goto :fail
echo.
echo === 2/4  Anthropic API key ===
call firebase functions:secrets:access ANTHROPIC_API_KEY --project studyapp-28624-6558e >nul 2>&1
if errorlevel 1 (
  echo Paste your Anthropic API key when asked ^(it is stored in Google Secret Manager, not in the app^).
  call firebase functions:secrets:set ANTHROPIC_API_KEY --project studyapp-28624-6558e || goto :fail
) else (
  echo Key already stored. To replace it run: firebase functions:secrets:set ANTHROPIC_API_KEY
)
echo.
echo === 3/4  Email account for sending plans ===
call firebase functions:secrets:access SMTP_USER --project studyapp-28624-6558e >nul 2>&1
if errorlevel 1 (
  echo Enter the Gmail address the plan emails are sent FROM:
  call firebase functions:secrets:set SMTP_USER --project studyapp-28624-6558e || goto :fail
  echo Enter that account's 16-letter Gmail APP PASSWORD ^(not the normal password^):
  call firebase functions:secrets:set SMTP_PASS --project studyapp-28624-6558e || goto :fail
) else (
  echo Email account already stored.
)
echo.
echo === 4/4  Deploying ===
call firebase deploy --only functions --project studyapp-28624-6558e || goto :fail
echo.
echo Done. In the app: AI Planner ^> Generate ^> Apply. The plan is emailed to the student.
pause
exit /b 0
:fail
echo.
echo Something failed - read the message above. See CLAUDE_AI_SETUP.md.
pause
exit /b 1
