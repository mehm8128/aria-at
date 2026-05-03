# README

## 手順

### NVDAの設定

1. `nvda-at-automation/NVDAPlugin`ディレクトリを`nvda/addons`にコピーし、プラグインを再読み込み
2. NVDAの音声の設定で、「音声エンジン」を「Capture Speech」に切り替える
3. `curl http://localhost:8765/info`が通ることを確認

### at-driverの起動

1. `nvda-at-automation/Server`ディレクトリで`go build ./main/main.go`を実行
2. `./main.exe`を実行
3. `Test-NetConnection 127.0.0.1 -Port 3031`が通ることを確認

### chromedriverの起動

1. https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json から、使用しているChromeのバージョンに対応するchromedriverをダウンロード
2. `./chromedriver.exe --port=4444`を実行
3. `curl.exe http://127.0.0.1:4444/status`が通ることを確認

### テストの生成

1. `pnpm i`を実行
2. `pnpm build`を実行
3. `build`ディレクトリ以下にテストコードが生成される

テストケースを追加したいときは、`tests`ディレクトリ以下に必要なコードを追加し、`pnpm build`を再実行。

### テストの実行

先に以下を確認しておく。

- NVDAの言語設定が英語になっていること
  - 日本語のままだと失敗する
- `NVDAキー+S`で読み上げが消音モードになっていないこと

1. `aria-at-automation-harness`で`npm ci`を実行
2. 以下のコマンドを実行。ただし、`--plan-workingdir`の指定と最後の`summary.json`は必要に応じてパスを修正すること

```jq
node bin/host.js run-plan --plan-workingdir ../aria-at/build/tests/aria/test-case "{reference/**,test-*-nvda.*}" --web-driver-url=http://127.0.0.1:4444 --at-driver-url=ws://127.0.0.1:3031/session --reference-hostname=127.0.0.1 --web-driver-browser=chrome | jq -f ../extract-result.jq | Out-File -Encoding utf8 ../summary.json
```

3. `summary.json`にテスト結果が出力される

## 参考

- [ARIA-ATのNVDA操作自動化調査メモ - mehm8128](https://scrapbox.io/mehm8128/ARIA-AT%E3%81%AENVDA%E6%93%8D%E4%BD%9C%E8%87%AA%E5%8B%95%E5%8C%96%E8%AA%BF%E6%9F%BB%E3%83%A1%E3%83%A2)
- [テストの一覧 | as_test](https://waic.github.io/as_test/WAIC-TEST/HTML/)
