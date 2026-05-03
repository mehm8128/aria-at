# =============================================================================
# run-tester.ps1
# -----------------------------------------------------------------------------
# nvda-test ワークフローから呼ばれるテストランナー。
# 以下のサービスを順に起動し、最後に aria-at-harness-host を実行する。
#
#   1. NVDA (portable zip を展開して --debug-logging で起動)
#   2. at-driver        : NVDA を WebSocket 経由で操作するための Go サーバ
#   3. webdriver        : ブラウザ操作 (chromedriver / geckodriver / msedgedriver)
#   4. aria-at-harness  : 上記 2 つを組み合わせてテストを実行
#
# 期待する環境変数:
#   NVDA_PORTABLE_ZIP   : NVDA portable zip のフルパス (ワークフローから渡される)
#   JAWS_VERSION        : (任意) JAWS 利用時のバージョン
#   BROWSER             : "chrome" | "firefox" | "MicrosoftEdge"
#   ARIA_AT_WORK_DIR    : aria-at/build/ 配下のテスト対象ディレクトリ
#   ARIA_AT_TEST_PATTERN: テストファイルの glob パターン
# =============================================================================

# NVDA portable zip のファイル名 (拡張子なし) = 展開後のフォルダ名 / バージョン名
[string]$nvdaVersion = [System.IO.Path]::GetFileNameWithoutExtension($env:NVDA_PORTABLE_ZIP)
$loglocation = $pwd

Write-Output "Log folder $loglocation"

# -----------------------------------------------------------------------------
# Wait-For-HTTP-Response
# 指定 URL に最大 30 秒間 (1秒×30回) リトライ接続する。
# 4xx / 5xx でも「サーバが起動して応答を返している」とみなして成功扱い。
# サービス起動完了の同期ポイントとして使用。
# -----------------------------------------------------------------------------
function Global:Wait-For-HTTP-Response {
  param (
    $RequestURL
  )

  $status = "Failed"
  for (($sleeps=1); $sleeps -le 30; $sleeps++)
  {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $RequestURL >> $loglocation\http-testing.log
      $status = "Success"
      break
    }
    catch {
      # HTTP ステータスコードが返ってきていれば「起動済み」とみなす
      $code = $_.Exception.Response.StatusCode.Value__
      if ( $code -gt 99)
      {
        $status = "Success ($code)"
        break
      }
    }
    Start-Sleep -Seconds 1
  }
  Write-Output "$status after $sleeps tries"
}

# -----------------------------------------------------------------------------
# NVDA + at-driver の起動
# -----------------------------------------------------------------------------
if ($env:NVDA_PORTABLE_ZIP)
{
  # zip と同じ階層に展開
  [string]$nvdaFolder = [System.IO.Path]::GetDirectoryName($env:NVDA_PORTABLE_ZIP)
  Expand-Archive -Path "$env:NVDA_PORTABLE_ZIP" -DestinationPath "$nvdaFolder"
  Write-Output "Starting NVDA $nvdaVersion - $nvdaFolder\$nvdaVersion\nvda.exe"
  & "$nvdaFolder\$nvdaVersion\nvda.exe" --debug-logging

  # NVDA は localhost:8765 にリモート操作 API を立ち上げる。
  # 注意: 一度ここで叩いておかないと後続の at-driver 起動が失敗する既知の問題あり。
  Write-Output "Waiting for localhost:8765 to start from NVDA"
  Wait-For-HTTP-Response -RequestURL http://localhost:8765/info

  # at-driver を別ジョブとしてバックグラウンド起動。
  # 標準出力/エラーを at-driver.log にリダイレクト。
  Write-Output "Starting at-driver"
  $atprocess = Start-Job -Init ([ScriptBlock]::Create("Set-Location '$pwd\nvda-at-automation\Server'")) -ScriptBlock { & .\main.exe 2>&1 >$using:loglocation\at-driver.log }
  Write-Output "Waiting for localhost:3031 to start from at-driver"
  Wait-For-HTTP-Response -RequestURL http://localhost:3031

  # harness が接続する WebSocket URL
  $atDriverUrl = "ws://127.0.0.1:3031/session"
}

# JAWS の場合は別ポート (このリポジトリでは未使用、参考に残してある)
if ($env:JAWS_VERSION)
{
  $atDriverUrl = "ws://127.0.0.1:9002/session"
}

# -----------------------------------------------------------------------------
# WebDriver の起動 (ブラウザ別)
# どのブラウザでも localhost:4444 で待ち受ける。
# -----------------------------------------------------------------------------
switch ($env:BROWSER)
{
  chrome
  {
    Write-Output "Starting chromedriver"
    $webdriverprocess = Start-Job -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) -ScriptBlock { chromedriver --port=4444 --log-level=INFO *>&1 >$using:loglocation\webdriver.log }
    Write-Output "Waiting for localhost:4444 to start from chromedriver"
    Wait-For-HTTP-Response -RequestURL http://localhost:4444/
    Break
  }
  firefox
  {
    Write-Output "Starting geckodriver"
    $webdriverprocess = Start-Job -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) -ScriptBlock { geckodriver *>&1 >$using:loglocation\webdriver.log }
    Write-Output "Waiting for localhost:4444 to start from geckodriver"
    Wait-For-HTTP-Response -RequestURL http://localhost:4444/
    Break
  }
  MicrosoftEdge
  {
    Write-Output "Starting msedgedriver"
    $webdriverprocess = Start-Job -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) -ScriptBlock { msedgedriver --port=4444 *>&1 >$using:loglocation\webdriver.log }
    Write-Output "Waiting for localhost:4444 to start from msedgedriver"
    Wait-For-HTTP-Response -RequestURL http://localhost:4444/
    Break
  }
  default
  {
    throw "Unknown browser"
  }
}

# -----------------------------------------------------------------------------
# 全モニタを覆う領域を計算してスクリーンショット用の Bitmap を準備。
# テスト前 / テスト後 / notepad 起動後の 3 タイミングで撮る。
# (ヘッドレス Windows ランナーで実際に何が起きたかをデバッグするため)
# -----------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$screens = [Windows.Forms.Screen]::AllScreens
$top    = ($screens.Bounds.Top    | Measure-Object -Minimum).Minimum
$left   = ($screens.Bounds.Left   | Measure-Object -Minimum).Minimum
$width  = ($screens.Bounds.Right  | Measure-Object -Maximum).Maximum
$height = ($screens.Bounds.Bottom | Measure-Object -Maximum).Maximum
$bounds   = [Drawing.Rectangle]::FromLTRB($left, $top, $width, $height)
$bmp      = New-Object System.Drawing.Bitmap ([int]$bounds.width), ([int]$bounds.height)
$graphics = [Drawing.Graphics]::FromImage($bmp)

# テスト開始前の画面状態を test.png に保存
$graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size)
$bmp.Save("$loglocation\test.png")


# -----------------------------------------------------------------------------
# aria-at-harness-host の起動 (テスト本体)
# - --plan-workingdir : aria-at/build/<work_dir> (テストプランの場所)
# - 引数の最後の要素 ($env:ARIA_AT_TEST_PATTERN) はテストファイルの glob
# - --web-driver-url  : 上で起動した webdriver
# - --at-driver-url   : 上で起動した at-driver (NVDA / JAWS)
# - 実行ログは harness-run-<planName>.log に保存 (Tee-Object)
#
# ARIA_AT_WORK_DIR が以下のどちらかに応じて挙動を変える:
#   - 「葉」(test-* ファイルを直接含むプランディレクトリ)
#       → そのディレクトリのみで harness を 1 回実行
#   - 「親」(プランディレクトリの集合)
#       → 配下の各プランで harness をループ実行
#         (例: tests/aria を渡すと aria-describedby-text-input,
#              link-with-image-and-text などをそれぞれ実行)
# -----------------------------------------------------------------------------
Write-Output "Launching automation-harness host"
$hostParams = "--debug"

$buildPath = "aria-at/build/$env:ARIA_AT_WORK_DIR"

# ビルド出力に test-* ファイルが直接あれば「葉」、なければサブディレクトリ群とみなす
$hasTestFiles = @(Get-ChildItem -Path $buildPath -Filter "test-*" -File -ErrorAction SilentlyContinue).Count -gt 0

if ($hasTestFiles) {
  $plansToRun = @($env:ARIA_AT_WORK_DIR)
} else {
  # 親ディレクトリのケース。test-* ファイルを含むサブディレクトリだけを抽出
  # (data/ や _shared/ のような非プランディレクトリを除外する目的)
  $plansToRun = Get-ChildItem -Path $buildPath -Directory -ErrorAction SilentlyContinue | Where-Object {
    @(Get-ChildItem -Path $_.FullName -Filter "test-*" -File -ErrorAction SilentlyContinue).Count -gt 0
  } | ForEach-Object {
    "$($env:ARIA_AT_WORK_DIR)/$($_.Name)"
  }
}

Write-Output "Plans to run ($($plansToRun.Count)): $($plansToRun -join ', ')"

foreach ($plan in $plansToRun) {
  # ログファイル名はプランディレクトリの末尾セグメントを使う
  $planName = ($plan -split '[/\\]')[-1]
  Write-Output "===== Running harness for $plan -> harness-run-$planName.log ====="
  ./node_modules/.bin/aria-at-harness-host run-plan --plan-workingdir "aria-at/build/$plan" $env:ARIA_AT_TEST_PATTERN $hostParams --web-driver-url=http://127.0.0.1:4444 --at-driver-url=$atDriverUrl --reference-hostname=127.0.0.1 --web-driver-browser=$env:BROWSER | Tee-Object -FilePath "$loglocation\harness-run-$planName.log"
}

# テスト直後の画面状態を test2.png に保存
$graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size)
$bmp.Save("$loglocation\test2.png")


# -----------------------------------------------------------------------------
# notepad を起動して 10 秒待ってからもう 1 枚スクショ。
# (デスクトップが生きていることの確認、& おまじない的な意味)
# -----------------------------------------------------------------------------
Write-Output "Opening notepad for good luck (and screenshot purposes)"
Start-Process notepad

Start-Sleep -Seconds 10
$graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size)
$bmp.Save("$loglocation\test3.png")
$graphics.Dispose()
$bmp.Dispose()

# -----------------------------------------------------------------------------
# 後片付け
# - プロセス一覧を get-process.log に保存 (ハング調査用)
# - NVDA 自身のログ (TEMP\nvda.log) も artifact に含めるためコピー
# -----------------------------------------------------------------------------
Set-Location ..
get-process > .\get-process.log

if ($env:NVDA_PORTABLE_ZIP)
{
  Copy-Item -Path $env:TEMP\nvda.log -Destination $loglocation -ErrorAction Continue
}
