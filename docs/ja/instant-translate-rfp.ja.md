# RFP: instant-translate

> Generated: 2026-07-19
> Status: Draft

> **スコープ変更（2026-07-19）:** トリガー③の*選択テキスト翻訳*（Accessibility 権限が
> 必要だったもの）は Phase 2 で**中止**。これにより本アプリは**特別な権限を一切必要と
> しない**（OS の言語モデルDL同意のみ）。§5 の「Accessibility 権限」は該当しなくなった。
> 「見ているものを翻訳する」用途はグローバルホットキー＋クリップボード seed でカバーする。
> それ以外は当初計画どおり実装済み。

## 1. Problem Statement

**instant-translate** は、macOS の Translation framework（オンデバイス翻訳）を使う
軽量なメニューバー常駐翻訳アプリである。ユーザーはメニューバーからパネルを開いて
原文を入力/貼付するか、グローバルホットキー、または他アプリでの選択テキストから
即座に翻訳を起動し、訳文を確認・コピーして再利用できる。数十GBの LLM モデルを
ロードする既存の `quick-translate`（ローカル LLM 版）と異なり、OS 標準の
オンデバイスモデル（初回のみ同意 DL・軽量）を使うため、起動が速くメモリ負荷が
小さい。ターゲットユーザーは開発者本人を含む、日常的に短文翻訳をサッと済ませたい
macOS ユーザー。`quick-translate` とは用途で使い分ける共存関係（同 UX・別バックエンド）。

## 2. Functional Specification

### Commands / API Surface

GUI 専用アプリ（CLI サブコマンドなし）。メニューバー常駐（NSStatusItem / MenuBarExtra）で、
以下の 3 トリガーから翻訳パネルを起動する。

1. **メニューバーから直接入力** — アイコンクリックでパネルを展開し、原文欄に
   入力/貼付 → 訳文表示 → コピー。追加権限不要の最小経路。
2. **グローバルホットキー** — ショートカットでどこからでもパネルを即起動。
   クリップボードの内容を自動的に原文欄へ流し込む挙動をオプションで提供。
3. **選択テキスト翻訳** — 他アプリで選択中のテキストをホットキーで取得して翻訳
   （`Cmd+C` 合成 → ペーストボード読取方式）。Accessibility 権限が必要。

パネルは「原文入力欄 / 訳文表示欄 / コピー・言語切替コントロール」で構成する。

### Input / Output

- 入力: テキスト入力・クリップボード・他アプリ選択テキスト
- 出力: パネル上の訳文表示 + クリップボードへのコピー
- パイプ/標準入出力・ファイル入出力は扱わない（GUI I/O のみ）

### 言語処理

- **原文言語は自動認識**（Translation framework の言語検出）
- 出力先の既定はシステムのローカルロケール（例: `ja`）
- **入力がローカルロケールと同一言語と判定された場合は、設定で選んだ二次ロケール
  （例: `en`）へ出力を自動スワップ**する。この自動処理は設定で ON/OFF 可能
- 実質「外国語 → 自国語 / 自国語 → 設定した外国語」の賢い双方向動作となる

### 履歴

- 直前 1 件のみをメモリ上に保持
- **永続化しない**（アプリ終了で揮発）

### Configuration

- 設定値は `UserDefaults` に永続化し、SwiftUI の Settings 画面で編集
- 設定項目: 二次ロケール、自動スワップの ON/OFF、ホットキー割当、
  クリップボード自動翻訳の ON/OFF など

### External Dependencies

- 外部サービス・API・クレデンシャル: **なし**
- OS の Translation framework（オンデバイス）のみに依存
- ネットワークはアプリとして不要（言語モデル DL 時のみ OS 側が通信し、アプリは関与しない）
- グローバルホットキー実装は Carbon `RegisterEventHotKey` を基本とする
  （追加ライブラリ採用は実装時に判断）

## 3. Design Decisions

- **なぜ Swift/SwiftUI か**: Translation framework は Swift/SwiftUI ネイティブであり、
  `TranslationSession` は SwiftUI ビューに紐付けて取得する設計。メニューバー GUI も
  SwiftUI が最適。既存の Swift メニューバーアプリ群（`quick-translate`,
  `claude-usage-lens-gui`, `active-lens-gui`）と技術スタックが揃う。
- **なぜ Apple Translation か**: `quick-translate` の数十GB LLM ロードの重さ
  （起動遅延・メモリ負荷）を解消するため。オンデバイス・軽量・OS 管理モデルを採用。
- **補完する nlink-jp ツール**: `quick-translate` の軽量姉妹（同 UX・別バックエンド・共存）。
  util-series の macOS GUI アプリ群に属する。
- **明示的スコープ外**:
  - CLI / パイプ連携（GUI 専用）
  - 翻訳履歴の永続化
  - OCR による画面翻訳（SwiftyCrow 的なもの。将来検討）
  - macOS 25 以前・iOS
  - 独自/カスタム翻訳エンジン（翻訳品質は OS に委ねる）

## 4. Development Plan

### Phase 1: Core

- メニューバー常駐 + 翻訳パネル UI
- `TranslationSession` のホスト（閉パネル時経路のための隠し SwiftUI ホストビュー常駐を含む）
- 直接入力からの翻訳
- 言語自動処理（自動認識 + ローカルロケール判定 + 二次ロケール自動スワップ）
- 訳文コピー、直前 1 件の揮発保持
- テスト: 言語決定ロジックを純関数として切り出しユニットテスト。
  `TranslationSession` は依存性注入 / モックでテスト可能に設計

### Phase 2: Features

- グローバルホットキー
- クリップボード自動翻訳
- 選択テキスト翻訳（Accessibility）
- SwiftUI Settings 画面
- 言語モデル未 DL / 同意プロンプト / 未対応ペアのハンドリング（`LanguageAvailability`）

### Phase 3: Release

- README.md / README.ja.md、CHANGELOG.md、AGENTS.md の整備
- Developer ID 署名 + notarize
- Homebrew tap（arm64 専用 prebuilt-binary）
- umbrella submodule ポインタ更新
- org profile / web-site catalog（EN + JA）更新
- `check-org.sh` 全 green

### 独立レビュー可能な区切り

- Phase 1（コア翻訳経路）と Phase 2（トリガー拡張・権限系）は分離してレビュー可能

## 5. Required API Scopes / Permissions

- **Accessibility 権限（TCC）**: 選択テキスト翻訳で `Cmd+C` を合成し、
  ペーストボードから選択テキストを取得するために必要。
- **Translation 言語モデルの初回 DL 同意**: 未 DL の言語ペアを使う際、OS が
  ユーザー同意プロンプトを表示する。アプリ側は `LanguageAvailability` で
  DL 状態を事前判定してハンドリングする（アプリから同意を抑制することはできない）。
- **グローバルホットキー**: Carbon `RegisterEventHotKey` を用いれば追加の TCC 権限は不要。
- **OAuth / IAM スコープ**: なし（外部サービスに接続しないため）。

## 6. Series Placement

Series: **util-series**
Reason: 汎用ローカルユーティリティの macOS GUI アプリであり、既存の `quick-translate`
をはじめとする util-series の GUI アプリ群（`claude-usage-lens-gui`, `active-lens-gui`,
`image-forge-gui` 等）と同じ位置づけ。外部サービス連携もセキュリティ用途もないため
他シリーズには該当しない。

## 7. External Platform Constraints

macOS **Translation framework** に由来する制約:

- `TranslationSession` は直接インスタンス化できず、`.translationTask()` を
  SwiftUI ビューに付与して取得する。→ パネルを閉じた状態でも翻訳する経路
  （ホットキー / 選択テキスト）のために、セッションをホストする隠しビューを常駐させる。
- セッションはホストビューのライフタイムに束縛され、ビューが消滅すると無効化される。
  セッションをビューの生存期間を超えて保持してはならない。
- 対応言語は OS が提供する範囲に限定され、任意の言語ペアは扱えない。
  未対応 / 未 DL のペアは `LanguageAvailability` で事前判定してハンドリングする。
- 言語モデルの初回 DL はユーザー同意が必須で、DL 自体は OS が管理する
  （アプリ側で抑制・自動化できない）。
- プログラマティック翻訳 API の都合上、macOS 26 専用とする。
- レート制限・ネットワーク制約はなし（ローカルオンデバイス処理のため）。

---

## Discussion Log

- **着想**: macOS 標準の翻訳 API（Translation framework）を知り、数十GB の LLM を
  ロードする既存 `quick-translate` の使い勝手の悪さを解消する軽量アプリを構想。
- **技術前提の確認**: Web 調査により、`TranslationSession` は SwiftUI の
  `.translationTask()` 経由でしか取得できない（直接生成不可・ビューのライフタイムに束縛）
  ことを確認。ただしメニューバーのポップオーバー自体が SwiftUI ビューであり、
  閉パネル時は隠しホストビューを常駐させれば実現可能で、既存事例（SwiftyCrow 等）も
  同構造であると確認。
- **位置づけの決定**: `quick-translate`（ローカル LLM）とは別の新規の姉妹アプリとして
  共存させる（置換・統合案は不採用）。同 UX・別バックエンドで用途により使い分ける。
- **トリガーの決定**: パネル直接入力・グローバルホットキー・選択テキスト翻訳の 3 種を
  すべて採用。選択テキスト翻訳には Accessibility 権限、閉パネル時翻訳には隠しホスト
  ビュー常駐が必要という含意を確認。
- **言語処理の決定**: 入力自動認識。出力既定はローカルロケールとし、入力が
  ローカルロケールと同一の場合は設定済み二次ロケールへ自動スワップする挙動を
  設定で選べるようにする。
- **履歴の決定**: 直前 1 件のみ・揮発（永続化不要）とし軽量性を優先。
- **CLI 同居の判断**: Translation framework がビューホストを要する制約と「軽量」の
  趣旨から、GUI 専用（CLI サブコマンドなし）とする。
- **最低 OS の決定**: macOS 26 専用（プログラマティック API の安定版を使い、
  実装・検証をシンプルにするため）。
- **命名**: `native-translate` / `menu-translate` / `instant-translate` / `lingo-bar` を
  比較し、ホットキーでの即時性を表す **instant-translate** に決定。
