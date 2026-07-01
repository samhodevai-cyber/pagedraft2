$root = Join-Path $PSScriptRoot "origin"
$imageDir = Join-Path $PSScriptRoot "image"
$port = 8731
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Serving $root on http://localhost:$port/"

$mime = @{
  ".html" = "text/html"; ".js" = "application/javascript"; ".css" = "text/css";
  ".png" = "image/png"; ".jpg" = "image/jpeg"; ".svg" = "image/svg+xml"; ".json" = "application/json";
}

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  try {
    $path = $req.Url.LocalPath

    if ($req.HttpMethod -eq "POST" -and $path -eq "/upload-image") {
      # 콘도 관리 카드 이미지 업로드: PNG 원본 바이트를 그대로 받아 image/ 폴더에 저장
      # 주의: $req.QueryString은 시스템 코드페이지로 디코딩되어 한글이 깨질 수 있으므로
      # 쿼리스트링을 직접 파싱해 [Uri]::UnescapeDataString으로 UTF-8 디코딩한다.
      $name = $null
      $rawQuery = $req.Url.Query.TrimStart('?')
      foreach ($pair in ($rawQuery -split '&')) {
        $kv = $pair -split '=', 2
        if ($kv[0] -eq 'name' -and $kv.Length -eq 2) { $name = [Uri]::UnescapeDataString($kv[1]) }
      }
      if ([string]::IsNullOrWhiteSpace($name)) { $name = "condo.png" }
      $name = $name -replace '[\\/:*?"<>|]', '_'  # 파일시스템에 쓸 수 없는 문자 제거
      if (-not (Test-Path $imageDir)) { New-Item -ItemType Directory -Path $imageDir | Out-Null }
      $destPath = Join-Path $imageDir $name

      $ms = New-Object System.IO.MemoryStream
      $req.InputStream.CopyTo($ms)
      [System.IO.File]::WriteAllBytes($destPath, $ms.ToArray())
      $ms.Dispose()

      # 콘도명==파일명 자동 매칭 기능(index10.html부터)이 참조하는 목록을 최신 상태로 갱신
      $imageFiles = Get-ChildItem -Path $imageDir -File | Where-Object { $_.Name -ne "README.txt" -and $_.Name -ne "manifest.json" } | ForEach-Object { $_.Name }
      $manifestJson = ($imageFiles | ConvertTo-Json)
      if ($imageFiles.Count -eq 1) { $manifestJson = "[$manifestJson]" }  # 파일이 1개면 배열이 아닌 문자열로 변환되는 ConvertTo-Json 특성 보정
      [System.IO.File]::WriteAllText((Join-Path $imageDir "manifest.json"), $manifestJson, [System.Text.Encoding]::UTF8)

      $resBody = [System.Text.Encoding]::UTF8.GetBytes("{`"ok`":true,`"path`":`"image/$name`"}")
      $res.ContentType = "application/json"
      $res.Headers.Add("Access-Control-Allow-Origin", "*")
      $res.ContentLength64 = $resBody.Length
      $res.OutputStream.Write($resBody, 0, $resBody.Length)
    }
    else {
      if ($path -eq "/") { $path = "/index12.html" }
      if ($path -like "/image/*") {
        $filePath = Join-Path $PSScriptRoot ($path.TrimStart("/"))
      } else {
        $filePath = Join-Path $root ($path.TrimStart("/"))
      }
      if (Test-Path $filePath -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($filePath)
        $ct = $mime[$ext]
        if (-not $ct) { $ct = "application/octet-stream" }
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $res.ContentType = $ct
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        $res.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes("Not found: $path")
        $res.OutputStream.Write($msg, 0, $msg.Length)
      }
    }
  } catch {
    $res.StatusCode = 500
  } finally {
    $res.OutputStream.Close()
  }
}
