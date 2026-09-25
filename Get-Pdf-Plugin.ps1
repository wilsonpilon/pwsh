mkdir C:\Tools\PdfPig -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/UglyToad.PdfPig" -OutFile C:\Tools\PdfPig\PdfPig.zip

Expand-Archive C:\Tools\PdfPig\PdfPig.zip C:\Tools\PdfPig -Force
