# ADR-0001: パネルの状態表示と失敗メッセージ

| 項目 | 内容 |
|------|------|
| Status | **Accepted** |
| Date | 2026-08-08 |
| Binds | instant-translate |
| Decision makers | nlink-jp maintainers |
| Triggered by | v0.2.0 後のユーザー報告 — 翻訳が動いているのかパネルが何も言わない。framework の失敗はすべて同じ役に立たない一文になる |

## Context

v0.2.0 に対する 2 つの指摘。どちらも「パネルが何も言わない」という同じ問題。

**1. エラーが読み取れない。** `PanelView.run` は例外を 1 行に潰している。

```swift
model.fail("Couldn't translate — the language model may still be downloading. \(error.localizedDescription)")
```

macOS 26.5 SDK で実測したところ、`TranslationError.localizedDescription` は
**8 ケース中 7 ケースが `"Unable to Translate"` に潰れる**
（異なるのは `nothingToTranslate` だけ）。区別できる文言は `failureReason`
側にあるが、このコードは一度も読んでいない。

| ケース | `localizedDescription` | `failureReason` |
|--------|------------------------|-----------------|
| `unsupportedSourceLanguage` | Unable to Translate | Translation from this language is not supported. … |
| `unsupportedTargetLanguage` | Unable to Translate | Translation into this language is not supported. … |
| `unsupportedLanguagePairing` | Unable to Translate | This language pairing is not supported. |
| `unableToIdentifyLanguage` | Unable to Translate | The language could not be automatically detected. |
| `nothingToTranslate` | Translation Request Empty | Please provide text to translate and try again. |
| `alreadyCancelled` | Unable to Translate | Translation was already cancelled. |
| `notInstalled` | Unable to Translate | Languages must be downloaded on-device. |
| `internalError` | Unable to Translate | Something went wrong. Please try again later. |

`NSError` ブリッジも助けにならない。全ケースがドメイン
`Translation.TranslationError` の **code 1**。結果として、未対応の言語ペアでも、
サービス内部エラーでも、本当にモデルが無い場合でも、ユーザーが見るのは同じ

> Couldn't translate — the language model may still be downloading. Unable to Translate

の一文になる。しかも前半は当て推量で、上記の大半のケースでは**誤り**であり、
積極的に誤解を招いている。

`TranslationError` は enum ではなく独自 `~=` を持つ struct なので、形状で
`switch` できない。8×8 の全マッチ行列を実機で確認したところ `~=` は完全な
対角行列で判別する（無関係なエラーや `CancellationError` はどれにもマッチ
しない）。つまり**正確な分類は可能で、単にやっていなかった**。

**2. 動作しているかどうかの表示がない。** `TranslationModel.isTranslating` は
存在し更新もされているが、どのビューも読んでいない。さらに悪いことに、
意図的に翻訳を**見送っている**状態も同様に不可視だった。

- 600 ms のデバウンスが待機中（入力は止まったが、まだ何も始まっていない）
- IME 変換中で `AutoTranslatePolicy` が全部止めている（v0.1.2）
- 入力がまだどの言語とも判定できず、OS の原文言語ピッカーを出さないために
  自動実行が見送られている（v0.2.0）
- source と target が同一言語に解決され、入力をそのままエコーしている
  — 出力が入力と同一なのに理由が示されない
- ペアの OS 言語モデルが未ダウンロードで、そのペアの初回翻訳が長時間
  ブロックする（説明なし）

いずれも挙動としては正しい判断だったが、いずれも無言である。合わさると
「設計どおり動いているのに壊れて見えるパネル」になる。

2 つの指摘は、パイプラインの別々の地点に現れた同一の欠陥である
— **パネルは自分の状態を知っていて、それを言わない**。

## Decision

### Decision 1: framework の失敗を分類し、人間向けの言葉にする

新しい `TranslationFailure` enum が、このアプリが遭遇しうる失敗をすべて
命名する — `TranslationError` の 8 ケース、自前の
`LanguageAvailability` 事前判定による却下、そしてエラーから取れる文言を
そのまま抱える `unknown` の受け皿。

`TranslationFailure.classify(_:)` が framework に触れる唯一の場所で、`~=` で
マッチし、外れたら `unknown(failureReason ?? localizedDescription)` に落とす。
`TranslationFailure.message(sourceName:targetName:)` は**純関数**でユニット
テスト対象。3 つのフィールドを返す。

- **headline** — 何が起きたか。実際の言語名を含める
  （「macOS can't translate Japanese → Korean.」）
- **recovery** — ユーザーに何ができるか。**どのコントロールを操作するか**まで
  書く（「Choose a different target language with the right picker.」）
- **detail** — 技術的タグ（`TranslationError.unsupportedLanguagePairing`）。
  小さく・等幅・選択可能で描画する

detail 行の存在理由は v0.1.3 でパネル見出しに版数を出したのと同じ。この
アプリにはメニューバーも About 項目もログファイルも無いため、不具合報告に
書ける情報は**パネルに出ているものだけ**。コピー可能な正確な原因 ＋
コピー可能な正確なビルド、これが診断面の全体である。

### Decision 2: フェーズモデルを 1 本のステータス行として出す

`TranslationModel.isTranslating: Bool` を `TranslationModel.phase:
TranslationPhase` に置き換え、上記の全状態を表現する。

```
idle · composing · awaitingLanguage · pending · preparing · translating · echoed · done · failed
```

`isTranslating` は計算プロパティ（`preparing` または `translating`）として
残し、既存の呼び出し側とテストをそのまま生かす。

言語ピッカーと訳文の間に、**常時表示**のステータス行を 1 本置く。
`TranslationStatus.display(...)` がフェーズを シンボル / 文言 / スピナー /
トーン に写す**純関数**でユニットテスト対象 — `LanguagePolicy` や
`AutoTranslatePolicy` で既に使っている分離と同じ形。行は常に描画するので
レイアウトが跳ねない。`idle` かつ入力あり・自動翻訳オフのときは、無言では
なく手動ショートカットを案内する。

### Decision 3: 言語モデルを明示的に準備し、それを表示する

未インストールのペアの初回翻訳を `session.translate` の内側で黙ってブロック
させるのではなく、`PanelView.run` が `session.isReady` を確認し、false なら
`preparing` に入って `session.prepareTranslation()` を呼んでから翻訳する。

これは「アプリが避けていたダイアログを増やす」ものではない。そのペアの
ダウンロード同意はどちらにせよ OS が出す。**パネルが既にラベルを付けた瞬間**
（「Preparing the Japanese → English language model — the first use downloads
it…」）に移動させ、説明のない数秒のフリーズをやめるということ。

これは OS の**原文言語**ピッカーに対する v0.2.0 の姿勢（絶対に出させない）
より意図的に狭い。あちらは回避可能で、文の途中で入力を妨げる。こちらの
モデルダウンロードは必須・ペアごとに一度きり・ユーザーが承知のうえで同意
すべきものである。

## Consequences

- 失敗が、原因・関係する言語・次にとるべき行動を名指しする。旧文言が唯一
  正しく説明できていた `notInstalled` についても、待つ以外の選択肢として
  システム設定 › 一般 › 言語と地域 › 翻訳言語 を案内するようになる
- 不可視だった 5 つの状態が可視になる。うち 2 つ（IME 変換中・言語判定不能）は
  「正しく何もしていない」状態で、最もハングに見えるもの
- エコー経路（source == target）が理由を述べるようになる。入力がそのまま
  返ってくる理由が分かる
- `TranslationFailure` と `TranslationStatus` は、ビュー・セッション・実際の
  入力メソッドなしでテストできる。`classify` もテスト可能
  （`TranslationError` の各ケースは public な値として構築できる）
- ステータス行は最小高 280 pt のパネルで縦 1 行を消費する。パネルは
  ユーザーがリサイズできるので許容
- 挙動としては `prepareTranslation()` の明示呼び出し以外は純粋な追加。
  この 1 点も OS のダウンロード同意が出る**タイミング**を変えるだけで、
  出るかどうかは変えない
- 設定項目は増やさない。各状態は自分で名乗るか、そもそも存在しないかの
  どちらかである

## Alternatives considered

**A1. エラー行は 1 行のままにして `failureReason` を末尾に足すだけ。**
最も安価で、最悪の症状（全失敗が同じに読める）は消える。却下した理由は、
Apple の `failureReason` はこのアプリを知らないシステムダイアログ用の文言
だから。「Please try another language」は**2 つのピッカーのどちらを触れば
よいか**を言えないし、そのペアを作ったのが source ピンなのか target
オーバーライドなのかにも触れられない。文言を自分で持つことが「行動できる
メッセージ」の条件であり、純関数 1 つで済む。

**A2. `failureReason` は完全に捨てて自前の文言だけにする。** 逆方向の理由で
却下。`classify` が置き場所を決められなかったとき、Apple の文字列が残された
唯一の情報になる。それを捨てると、**まさに我々が想定できなかったケースで
元のバグを再現する**ことになる。`unknown` がそれを運ぶ。

**A3. スピナーだけ。フェーズモデルは作らない。** スピナーは「動いているか」に
答えるが、指摘の難しい方の半分「なぜ何も動いていないのか」には答えない。
デバウンス待ち・IME 保留・言語判定不能はすべて idle と見分けがつかない。
Bool ではこれらを区別できない。

**A4. エラーはインラインブロックではなくトースト／アラートで。** 却下。
パネルは非アクティブ化で閉じるため、一時的なトーストは読まれる前に消えうる。
アラートは、ユーザーが文の途中で使っているテキストフィールドからフォーカスを
奪う。インラインブロックは、その失敗が現在の状態である間だけ、正確にその間
表示される。

**A5. 翻訳中の Cancel ボタン。** `TranslationSession.cancel()` は macOS 26 に
ある。今回は却下。`PanelView` が `.translationTask` のクロージャ外でセッションを
保持する必要があり、それは framework が意図的に提供していないライフタイム
モデルである。加えて、報告された問題（動いているのか止まっているのか）は
ステータス行で解消する。実際に長時間かかるケースが出てきたら再検討。

**A6. モデル未取得の検出を `session.isReady` ではなく
`LanguageAvailability.status(from:to:) == .supported` で行う。** どちらも
可能で、事前判定は未対応チェックのために既に `status(from:to:)` を呼んでいる。
**ゲートとしては**却下した。`isReady` は実際に走るセッション自身の性質だが、
`status` は抽象的なペアの性質を述べる。セッション自身の答えを使えば、両者が
食い違う一群のケースが消える。`status` は「セッションを使う前に未対応ペアを
弾く」という既存の役割を保つ。

## References

- `Translation.framework` インターフェース (macOS 26.5 SDK) — `TranslationError`,
  `TranslationSession.isReady`, `prepareTranslation()`, `LanguageAvailability.Status`
- v0.1.2 — IME 変換中のゲート（`AutoTranslatePolicy`）
- v0.1.3 — 不具合報告のためのパネル見出しの版数表示
- v0.2.0 — OS の原文言語ピッカーを出させないための source 明示
