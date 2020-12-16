---
title: "アルパカでもわかる安全なPodの終了 - 実験編"
emoji: "🦙"
type: "tech"
topics: ["kubernetes"]
published: false
---

これはなに
---
この記事は[アルパカでもわかる安全なPodの終了]()の続編です。

前回は、Podの終了処理の動作を、Kubernetesを構成する各種コンポーネントの仕組みを踏まえつつ解説しました。
この記事では、実際にトラフィックを流しながらDeploymentのローリングアップデートを行い、このときのPodの終了に伴って発生するエラーを抑制することを試みてみます。

> 📘【note】
> この記事は[Kubernetes2 Advent Calendar 2020](https://qiita.com/advent-calendar/2020/kubernetes2)の18日目です。
> 昨日は@south37さんの[手を動かして学ぶコンテナ標準 - Container Runtime 編](https://south37.hatenablog.com/entry/2020/12/11/%E6%89%8B%E3%82%92%E5%8B%95%E3%81%8B%E3%81%97%E3%81%A6%E5%AD%A6%E3%81%B6%E3%82%B3%E3%83%B3%E3%83%86%E3%83%8A%E6%A8%99%E6%BA%96_-_Container_Runtime_%E7%B7%A8)でした。


安全にPodを終了するための2つの対策
---
Podが安全に終了するためにできることは大きく2つがあります。以下にそれぞれの概要を記します。
詳細については[前回の記事]()を参照ください。

#### preStopフックでのスリープ
preStopフックはKubernetesの機能で、コンテナに終了を指示する前に実行される前処理（フック）を定義する機能です。
preStopフックで一定時間の `sleep` を行うことで、Podへのトラフィックの配送が止まってから（サービスアウト）終了処理に入るようにすることができます。

<!-- 図 -->

サービスアウトとPodの終了は独立して実行されるため、サービスアウトを待ってpreStopフックを抜けるといったような、依存関係はもたせられないことに注意してください。
このため、サービスアウトされてから終了処理に入ることを保証することはできません。

#### アプリケーションでのGraceful Shutdown
Graceful Shutdownは、アプリケーションの終了処理において、その時点で受け付けているリクエストの処理を完了してから終了するというものです。

<!-- 図 -->

アプリケーションの終了処理中の新規リクエストはエラーとなるというこに注意してください。

それでは、本当にこれらの対策が、Pod終了中のエラーの抑制に役立つのか、実験して確かめていきたいと思います。


実験の内容
---

### 実際に実施する作業
実験用のWeb APIをKubernetesクラスターにデプロイしておき、一定のトラフィックを送ります。
リクエストが送られている間に、Deploymentの再起動 (`kubectl rollout restart`) を行います。

<!-- 構成図 -->

実際の運用場面では、再起動というよりもローリングアップデートを実施することのほうが多いと思いますが、あくまでPodが順に停止・起動すれば実験としては足りるため、再起動で代替しています。

### アプリケーション
実験用のアプリケーションの概要は、以下のとおりです。

- cowweb-go
    - Go製のサンプルアプリケーション
    - https://github.com/hhiroshell/cowweb-go/tree/v1.1.1
    - 起動フラグで1リクエストの処理にかかるCPU負荷を調整できる（内部処理でループする回数を変えるだけなので単位は適当）
    - 起動フラグで終了時にGraceful Shutdownを行うかどうかを指定することができます

Graceful Shutdownは以下のような実装をしています。

- https://github.com/hhiroshell/cowweb-go/blob/v1.1.1/cmd/cowweb/serve.go#L53-L61

```go
		sig := make(chan os.Signal)
		defer close(sig)
		signal.Notify(sig, syscall.SIGTERM, os.Interrupt)
		<-sig
		if *shutdownGracefully {
			if err := server.Shutdown(context.Background()); err != nil {
				log.Print(err)
			}
		}
```

#### 負荷がけ装置
（なんか書く？）


### 実験条件

#### 1. preStopスリープの効果確認


#### 2. Graceful Shutdownの効果確認


実験結果
---

### preStopスリープの有無
- こんな2つの条件で比較します
- Before - After
- 何が起きているのか

### Graceful Shutdownの有無
- こんな2つの条件で比較します
- Before - After
- 何が起きているのか

結論
---
- preStopスリープ / Graceful Shutdown どちらも大事。それぞれ性質が違う
    - Graceful Shutdowmは始まってしまったリクエストの処理が中断されるのを防ぐ。おかしな状態になるのを防止できる。
    - preStopスリープはShutdown前にリクエストが流入するのを防ぐ
- それぞれ適用するレイヤーが違う


---
（以下メモ）

採用する実験データ
---

### preStopスリープの有無

- preStopスリープなし
    - l640-rep8-rps200/cowweb-ru-gs
- preStopスリープあり
    - l640-rep8-rps200/cowweb-ru-gs-slp8

### Graceful Shutdownの有無

- Graceful Shutdownなし
    - l1020-rep8-rps100/cowweb-ru-slp8
- Graceful Shutdownあり
    - l1020-rep8-rps100/cowweb-ru-gs-slp8
