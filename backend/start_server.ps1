Set-Location "C:\Users\darejas\Desktop\Aplicacion app\backend"
while ($true) {
    & ".\venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
    Start-Sleep -Seconds 5
}
