---
title: "kubeletのAPIを調べてみた"
emoji: "🦙"
type: "tech"
topics: ["kubernetes"]
published: false
---

これはなに
---
ひょんなことからkubeletのAPIを使った開発をしてみたくなりまして、そのための調査をしたので共有したいと思います。

自分は今までこれといって触る機会がなく、コンテナのメトリクスを取るのに使われているということで、たまーに「ああ、kubeletさんのAPIは今日も頑張ってくれているのだなぁ」と思いを馳せるくらいの温度感でした。Kubernetesエンジニアの多くが、同じような感想を持たれているのではないでしょうか。

そんな縁の下の力持ち、kubeletのAPIさん、この記事をきっかけに、今までより少しだけ身近に感じてくれたらいいなって、そんなふうに思います♪

> 📘【note】
> この記事は[Kubernetes Advent Calendar 2022](https://qiita.com/advent-calendar/2022/kubernetes)の19日目です。


どんなAPIがあるの
---
kubeletのAPIはドキュメントが無いようなので、コードを見ていくほかありません。

コードにかかれているハンドラのパスから、以下のようなAPIが生えていることがわかります。

- `/pods`
    - そのkubeleteがあるNode上の、Podリソースのリストを取得できる
- `/metrics/catvisor`
    - コンテナのCPU使用量などのメトリクスを取得できる
- `/metrics/probes`
    - Readiness / Livenss Probeの成否を集計したメトリクスを取得できる
- `/metrics/resource`
    - （確認する）
- `/checkpoint`
    - Kubernetes v1.25からalpha機能として提供されているCheckpoint Restoreで使われるAPI
    - `ContainerCheckpoint` フィーチャーゲートを有効にするとアクセス可能になる
    - Checkpoint Restore機能については、[KubeCon NA 2021のセッション](https://www.youtube.com/watch?v=0RUDoTi-Lw4)があります
- `/run`
    - kubectl runコマンドで使われているのではないか
- `/exec`
    - kubectl execコマンドで使われているのではないか
- `/attach`
    - kubectl execコマンドで使われているのではないか
- `/portForward`
    - kubecl port-forwardコマンドで使われているのではないか
- `/logs`
    - kubecl logsコマンドで使われているのではないか
- `/stats`
    - （確認する）
- `/debug/pprof`
    - pprofプロファイラのエンドポイント
- `/debug/flags/v`
    - kubeletで利用可能な起動フラグの一覧を取得できる

さすが普段意識することが少ないだけあって、kubectlコマンドで内部的に使われているものや、デバッグ用のエンドポイントが多くを占めています。

とはいえ、`/pods`、`/metris/probes` あたりは、良い使い道がありそうな気がします。

冒頭に書いた「kubelet APIを使った開発」では、DaemonSetとして各Nodeに配置するエージェントで、自分がいるNode上のPod一覧を `/pod` から取得しようと考えています。また、`/metrics/probes` は監視に役立ちそうです（ひょっとしてもうこれを使うのは一般的なのでしょうか）。


認証・認可の仕組み
---
kubeletのAPIにアクセスするには、（有効な場合は）認証・認可をパスする必要があります。

認証、認可とも、内部的には判定処理をKube API Serverに移譲する仕組みになっているようです。[ここ](https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/cmd/kubelet/app/auth.go#L42)で、認証・認可モジュールのオブジェクトを作っていて、それぞれ

- [DelegatingAuthenticatorConfig](https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/staging/src/k8s.io/apiserver/pkg/authentication/authenticatorfactory/delegating.go#L41)
- [DelegatingAuthorizerConfig](https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/staging/src/k8s.io/apiserver/pkg/authorization/authorizerfactory/delegating.go#L31)

というのが使われています。時間の都合でそこから先の中身までは確認できていませんが、それぞれgodocコメントを見る限り、API Serverに移譲する仕組みと考えられます。

```go
// DelegatingAuthenticatorConfig is the minimal configuration needed to create an authenticator
// built to delegate authentication to a kube API server
```

```go
// DelegatingAuthorizerConfig is the minimal configuration needed to create an authenticator
// built to delegate authorization to a kube API server
```

### 認証についてもう少し
認証の仕組みを少し調べてみると、[このあたり](https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/staging/src/k8s.io/apiserver/pkg/authentication/authenticatorfactory/delegating.go#L90)でサービスアカウントのトークンを使った認証が行われているように見えます。Kubernetes上にデプロイされたPrometheusがメトリクスを集めるときなどは、このあたりの仕組を使って認証されているのでしょうか。

### 認可についてもう少し
認可については、kubeletのAPIもKubernetesのRole/ClusterRoleリソースで権限を制御します（RBACの場合）。

権限の評価に使われるのは、`node` リソースで、APIのパスに応じて、[サブリソースで絞った権限を設定することができる](https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/pkg/kubelet/server/auth.go#L66
)ようです。

```go
//	/stats/*   => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=stats
//	/metrics/* => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=metrics
//	/logs/*    => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=log
```




### 使って見よう

#### 試した環境


- manifests

```yaml



```





