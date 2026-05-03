# aria-at-automation-harness の結果 JSON から
# 冗長なログを削ぎ落とし、テスト結果の本体だけを残す jq フィルタ。
#
# 残るフィールド:
#   - name                                        : テストプラン名
#   - tests[].id, .filepath                       : テスト識別子
#   - tests[].results[].presentationNumber        : 提示番号
#   - tests[].results[].capabilities              : NVDA / ブラウザ情報
#   - tests[].results[].commands[].command        : 送ったキーコマンド
#   - tests[].results[].commands[].response       : スクリーンリーダーの読み上げ内容
#   - tests[].results[].commands[].assertions     : 期待値 (verdict は常に null)
#
# 削除されるフィールド:
#   - tests[].log         (atDriverComms と speechEvent の生ログ)
#   - top-level .log      (上記の全テスト統合版・完全重複)
#
# 使い方 (PowerShell):
#   jq -f extract-result.jq as-02-01-result.json | Out-File -Encoding utf8 as-02-01-summary.json

{
  name,
  tests: [
    .tests[] | {
      id,
      filepath,
      results: [
        .results[] | {
          presentationNumber,
          capabilities,
          commands: [
            .commands[] | {
              command,
              response,
              assertions
            }
          ]
        }
      ]
    }
  ]
}
