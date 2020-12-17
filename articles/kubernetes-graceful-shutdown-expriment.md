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

### 実験の流れ
実験用のWeb APIをKubernetesクラスターにデプロイしておき、一定のトラフィックを送ります。
リクエストが送られている間に、Deploymentの再起動 (`kubectl rollout restart`) を行います。

<!-- 構成図 -->

実際の運用場面では、再起動というよりもローリングアップデートを実施することのほうが多いと思いますが、あくまでPodが順に停止・起動すれば実験としては足りるため、再起動で代替しています。

### アプリケーション
今回、実験用のサンプルアプリケーションを用意しています。アプリの概要は以下のとおりです。

- https://github.com/hhiroshell/cowweb-go/tree/v1.1.1
- Go製のサンプルアプリケーション
- 起動フラグで1リクエストの処理にかかるCPU負荷を調整できる（内部処理でループする回数を変えるだけなので単位は適当）
- 起動フラグで終了時にGraceful Shutdownを行うかどうかを指定することができます
- preStopフックはDeploymentのマニフェストに記述してデプロイします

ランダム値を生成する処理をループすることでCPU負荷がかかるようにしています。
ループ回数は起動フラグで調整できます。

- https://github.com/hhiroshell/cowweb-go/blob/823894c18cbdec4c796e6b91deab078034d75fb8/pkg/infrastructure/cowsay/slow_cowsay.go#L19-L27

```
	for i := 0; i < c.load; i++ {
		for j := 0; j < c.load; j++ {
			rand.Intn(len(cows))
		}
	}
	if moosage == "" {
		moosage = defaultMoosage
	}
	return cowsay.Say(cowsay.Phrase(moosage), randomCowType())
```

Graceful Shutdownは以下のように実装しています。
Go標準の `http.Server.Shutdown()` を使っています。
こちらも起動フラグで、Gracefulに終了するかどうかを指定できる仕掛けにしています。

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

preStopフックによるSleepは、このアプリケーションのDeploymentに記述します。
以下は、preStopフックとして `sleep 5` を実行している例です。

- https://github.com/hhiroshell/k8s-rolling-update-experiment/blob/master/cowweb/overlay-go/prestop-sleep.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cowweb
spec:
  template:
    spec:
      containers:
        - name: cowweb
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
```


### 実験してみた！
それでは実際に、preStopスリープの有無、Graceful Shutdownの有無を比較して、それぞれの効果を検証してみます。

#### 1. preStopスリープの効果確認
以下の3通りの条件での結果を比較してみます。
preStopスリープの時間を3通り(0s, 5s, 8s)に変え、それ以外の条件は同じにしてあります。

|#                          |条件1-0s   |条件1-5s   |条件1-8s
|-                          |-          |-          |-
|**preStopスリープ(s)**     |**0**      |**5**      |**8**
|Graceful Shutdown          |true       |true       |true
|レプリカ数                 |8          |8          |8
|CPU負荷フラグ              |l=640      |l=640      |l=640
|最大秒間リクエスト数(rps)  |200        |200        |200

結果は以下のとおりです。

|#                      |条件1-0s   |条件1-5s   |条件1-8s
|-                      |-          |-          |-
|総リクエスト数         |24060      |24060      |24060
|2xx 系レスポンス       |23008      |23900      |24060
|5xx 系レスポンス       |1052       |160        |0
|エラー率               |4 %        |1 %        |0 %
|平均レスポンス時間(ms) |23         |29         |29

preStopスリープを行わない(0s)のケースでは4%ほどがエラーとなっていますが、5sスリープすることによって1%に、8sでは全てがエラーなく処理できるという結果になりました。
この結果を見る限り、preStopフックにエラーを抑制する効果があるように見えますが、実際にはKubernetesとアプリケーションにはどのような状況が起きているのでしょうか。

以下の図は、ローリングアップデートに伴うPodの終了時の動作を描いたもので、preStopスリープの長さが十分でないためにエラーが発生するケースを表しています。

![](./images/kubernetes-graceful-shutdown-experiment-04.dio.svg)

注目すべき点は、kube-proxyによりiptablesが更新される前の時点でpreStopスリープが終わり、コンテナにSIGTERMが送信されていることです。
これは、コンテナへのトラフィックへの配送がまだ続いている（サービスアウトしていない）にも関わらず、コンテナが終了処理に入ってしまっていることを意味します。

実験用のGoアプリケーションは、（多くのプロダクションのアプリケーションも同様と思われますが）終了処理が始まると新規リクエストを受け付けることができません。
このため、早すぎるpreStopの終了によってエラーが発生してしまいます。

preStopスリープの時間を十分に取ることで、サービスアウトしてからコンテナが終了処理に入るようになり、上記のようにエラーを抑制することができています。

#### 2. Graceful Shutdownの効果確認
次に、Graceful Shutdownの効果を調べるために、以下2通りの条件で実験してみます。
Graceful Shutdownをする/しないの条件以外は同じにしてあります（CPU負荷フラグ、最大最大リクエスト数の値が先程と異なりますが、これの理由は後述します）。

|#                          |条件2-f    |条件2-t
|-                          |-          |-
|preStopスリープ(s)         |8          |8
|**Graceful Shutdown**      |**false**  |**true**
|レプリカ数                 |8          |8
|CPU負荷フラグ              |l=1024     |l=1024
|最大秒間リクエスト数(rps)  |100        |100

結果は以下のとおりです。

|#                      |条件2-f    |条件2-t
|-                      |-          |-
|総リクエスト数         |12060      |12060
|2xx 系レスポンス       |11416      |12060
|5xx 系レスポンス       |644        |0
|エラー率               |5 %        |0 %
|平均レスポンス時間(ms) |47         |48

Graceful Shutdownをしないケースでは5%ほどがエラー、するケースではそのエラーが0%となっています。
どうやらGraceful Shutdownにもローリングアップデート時のエラーを抑制する効果があるようですが、このケースではどのようなことが起こっているのでしょうか。

以下の図は、Graceful Shutdownによってエラーを抑制可能なケースでの、Pod終了時の動作を表しています。

<!-- （図も） -->

こちらのケースでは、kube-proxyによりipTablesが更新されてから（サービスアウトしてから）コンテナの終了処理に入っています。
一見なにも問題ないように見えますが、そうとは言い切れません。
サービスアウトされたとしても、それ以前に受け付けたリクエストの処理がまだ完了していないかもしれないからです。

こういったリクエストが残っている状態でGracefulでない終了を行ってしまうと、これらはエラーとなってしまいます。
上記の結果は、Graceful Shutdownによって、受け済みのリクエストの処理が完了してからコンテナを終了させたことによりエラーを解消した結果と考えられます。


preStopフックを長く取れはGraceful Shutdownは不要？
---
<!-- （結果を再掲） -->

|#                          |条件2-f    |条件2-t    |条件1-0s
|-                          |-          |-          |-
|preStopスリープ(s)         |8          |8          |8
|**Graceful Shutdown**      |**false**  |**true**   |**true**
|レプリカ数                 |8          |8          |8
|CPU負荷フラグ              |l=1024     |l=1024     |l=640
|最大秒間リクエスト数(rps)  |100        |100        |200


結果は以下のとおりです（Gatlingの集計結果を添付）。

|#                      |条件2-f    |条件2-t    |条件1-0s
|-                      |-          |-          |-
|総リクエスト数         |12060      |12060      |24060
|2xx 系レスポンス       |11416      |12060      |24060
|5xx 系レスポンス       |644        |0          |0
|エラー率               |5 %        |0 %        |0 %
|平均レスポンス時間(ms) |47         |48         |29


結論
---
- preStopスリープ / Graceful Shutdown どちらも大事。それぞれ性質が違う
    - Graceful Shutdowmは始まってしまったリクエストの処理が中断されるのを防ぐ。おかしな状態になるのを防止できる。
    - preStopスリープはShutdown前にリクエストが流入するのを防ぐ
- それぞれ適用するレイヤーが違う
