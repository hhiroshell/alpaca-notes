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

そんな縁の下の力持ち、kubeletのAPIさん、この記事をきっかけに、今までより少しだけ身近に感じてくれたらいいなと思います…。

> 📘【note】
> この記事は[Kubernetes Advent Calendar 2022](https://qiita.com/advent-calendar/2022/kubernetes)の19日目です。


### どんなAPIがあるの

コードにかかれているハンドラのパスから



### 認証・認可の仕組み

認証も認可も、Kube API Serverに移譲する仕組みになっている

ここで、認証・認可モジュールを作っていて、
- https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/cmd/kubelet/app/auth.go#L42

それぞれ `DelegatingAuthenticatorConfig`、`DelegatingAuthorizerConfig` を使っている。

#### 認証

認証戦略

- DelegatingAuthenticatorConfigが使われる

```
// DelegatingAuthenticatorConfig is the minimal configuration needed to create an authenticator
// built to delegate authentication to a kube API server
```

使える認証戦略は、以下のコードからわかる
- 認証戦略: https://kubernetes.io/ja/docs/reference/access-authn-authz/authentication/#%E8%AA%8D%E8%A8%BC%E6%88%A6%E7%95%A5

- https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/staging/src/k8s.io/apiserver/pkg/authentication/authenticatorfactory/delegating.go#L68



#### 認可

こっちはシンプルにdeleteしてる感じで割とシンプル。

- `nodes` リソースとそのサブリソース `proxy`, `stats`, `metrics`, `log` で権限が評価される様になっている
- アクセスしたAPIのパスに応じて、権限の評価に使うサブリソースが選択される仕組み

https://github.com/kubernetes/kubernetes/blob/804d6167111f6858541cef440ccc53887fbbc96a/pkg/kubelet/server/auth.go#L66

```go
//	/stats/*   => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=stats
//	/metrics/* => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=metrics
//	/logs/*    => verb=<api verb from request>, resource=nodes, name=<node name>, subresource=log
```



### 使ってみた




