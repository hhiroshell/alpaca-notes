---
title: "モノリスとマイクロサービスの間"
emoji: "🦙"
type: "tech"
topics: ["microservices"]
published: false
---

これはなに
---
モノリシック / マイクロサービス アーキテクチャ、システムのアーキテクチャはこれらの2つにひとつと捉えるのではなくて、中間の構成がありうると考えておくといろいろ幸せになれるんじゃないか、っていうことを書きます


目次
---
1. イントロダクション
2. モノリスらしさ、マイクロサービスらしさの指標
3. 俺たちにとっての理想のアーキテクチャを探す旅


1 . イントロダクション
---

<!-- ### モノリシック・アーキテクチャ
単一のアプリケーションとしてシステムを構築

- 単一の技術スタック
- アプリケーションの構成要素はプロセス内で呼び合う（コード上のメソッド呼び出し）
- アプリ全体がデプロイメントの一単位

（以下、モノリシックと書きます）


### マイクロサービス・アーキテクチャ
小規模なシステムの組み合わせでシステムを実装

- サービス毎に異なる技術スタック
- サービス同士がネットワーク経由で呼び合う（疎結合）
    - REST over HTTP、gRPC、非同期メッセージング...etc

個々のサービスがデプロイメントの⼀単位
（以下、「マイクロサービス」と書きます）

### モノリシック・アーキテクチャの課題
モノリシックはビジネス環境の変化に対応しにくい⇒マイクロサービス
モノリシック・アーキテクチャは、⼤規模化すると機能要素同⼠の依存関係
が複雑化しがち
⼀部の変更が全体にどう影響するか把握しにくい
⼤量の回帰テストなどのために、システムの更新に⻑い⼯期を要する
マイクロサービス
疎結合な連携⽅式のため、変更の影響範囲を個々のサービスに留められ
る
システムを（サービス単位で）素早く更新できる -->

### モノリシック / マイクロサービスの⼆元論
現実のシステムは必ずしもどちらかに決まるわけではない
モノリシックとマイクロサービス、2つに1つの⼆元論で考えがち。でもそ
んなに単純な話だろうか？
Monolith ( or ) MSA
モノリシックであっても、内部がきれいにモジュール化されていると「よく
設計されたモノリス」とか⾔ったりする
モノリシックとマイクロサービスの 間の状態 というのがありそう

### モノリック vs. マイクロサービス ⼆元論の弊害
マイクロサービスへの移⾏を阻む要因になっていないか？
ふたつにひとつと捉えていると、マイクロサービスへの移⾏が⼤きなジャン
プアップのように感じられる
何をどうしたら良いのか、具体的に考えにくい
実態以上に難易度が⾼いように感じられる
作業が⾒積もれないので投資対効果が判断できな

### モノリシックとマイクロサービスの間 - Spotifyのモジュラモノリス
https://engineering.shopify.com/blogs/engineering/deconstructing-monolith-designing-software-maximizes-developer-productivity
内部実装をモジュール化して依存関係を整理
コードベースは⼀本化し、ひとつのサーバーにすべてデプロイ（モノリシッ
クと同じ）
機能ドメインごとにモジュラー化して境界を設ける。
Reorganize Code: ビジネス機能を基準にコードを分けて管理
Isolate Dependencies: 公開APIを通じてコンポーネントを利⽤
Enforce Boundaries: 依存コンポーネントを明⽰的に宣⾔
マイクロサービスの弊害を避けた結果、妥当な落とし所がこれだった

### モノリシックとマイクロサービスの間 - Grafana Lokiのモノマイクロリス
モノリスとしてもマイクロサービスとしても利⽤可能
単⼀バイナリ、単⼀リポジトリで、モードを切り替えることで役割の異なる
サービスとして動作ように実装
単⼀デプロイ、マルチモード・分散配置のいずれでも利⽤可能
⼤規模運⽤に適応しつつ、開発体験を⾼めるための⼯夫の結果

### 果たしてこれらが全てを解決するか…？
他にもたくさんの考慮点が残っていそう
モジュールに分けるくらいなすでにやっているのだが…？
DBは分けるの分けないの？
コードベース⼀本化はビルド時間がつらいんじゃ…？
組織はどうしたらいいの？
...etc
...考えることがまだありそう。

### 脱⼆元論！
モノリシックとマイクロサービスの間は連続的
もっといろいろなアーキテクチャの状態があって、モノリシック∕マイクロ
サービスらしさの程度は連続的なはず
「らしさ」を決める基準があれば、今どの辺なのかわかる
（このへんとか？）
↓
Monolith <- - - - - - - ( 連続的な状態のつながり ) - - - - - - -> MSA

モノリシック∕マイクロサービス間のものさし
らしさを測ることで移⾏作業を細分化できるのでは
「モノリシック∕マイクロサービスらしさ」を測ることができれば
今どの辺りなのかがわかる（現状）
段階を分けて少しずつマイクロサービスに近づけられる（移⾏パス）
（今ここ）
↓
Monolith ｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜ MSA
↑
（次ここ）


2 . モノリスらしさ、マイクロサービスらしさの指標
---

モノリスらしさ、マイクロサービスらしさ
こういうものを定義したいのでした。
（今ここ）
↓
Monolith ｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜→｜ MSA
↑
（次ここ）

Monolithらしさ、MSAらしさの指標
認証/認可とフロントエンド
アプリケーションランタイム
コンポーネント間のアクセス⽅式
DB
コードベース
注）上記の項⽬には運⽤の観点（監視、ロギング）や組織論が⼊っていません

認証/認可とフロントエンド
バックエンドの分割が可能なように、認証/認可とフロントの構成を決めるこ
とがマイクロサービス化の前提。指すUXと実装難度を勘案して決める
コンポーネント毎のサーバーサイドレンダリング + SSO
ビュー統合サービス
APIゲートウェイ型（SPA + APIのみのバックエンド）
メルカリはAPIゲートウェイ型を選択した
https://logmi.jp/tech/articles/320198

アプリケーションラインタイムの分離
（下に⾏くほどマイクロサービスらしい構成）
1. よくないモノリス
2. プロセスの分離
3. バイナリセットの分離
4. サーバー(OS)の分離
考えて⾒たいこと
実現の難度が⾼いのはどの分離点か
コンポーネント毎のライフサイクルの独⽴性が得られる境界はどこか

DBの分離
1. データベース共有
2. スキーマとアクセス権の分離
3. コンテナDBによる分離
4. DBインスタンス分離
5. Polyglot Data Source
考えて⾒たいこと
実現の難度が⾼いのはどの分離点か
トランザクションが効かなくなる境界は
ライフサイクルの独⽴性が得られる境界は

コンポーネント間のアクセス⽅式の分離
1. よくないモノリス
2. Public SDKが整理され、実装されている（サーバー側の実装）
3. Public SDKのみでアクセスが⾏われている（クライアント側の実装）
4. REST / gRPCが実装されている（サーバー側の実装）
5. REST / gRPCのみでアクセスが⾏われている（クライアント側の実装）
考えて⾒たいこと
⾮同期メッセージングはどのレベルに⼊るか

モノリスらしさ、マイクロサービスらしさ - 出来上がったもの
（絵）


3 . 俺たちにとっての理想のアーキテクチャを探す旅
---

（なにか書く）