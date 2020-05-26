アルパカでもわかる Horizontal Pod Autoscaler
===

検証用のクラスターの構築
---
Metric Serverが構成済みのクラスターを用意する手順。


kindを使って3ノードクラスターを作成

```
$ kind create cluster --config ./kind-cluster-config.yaml
```

Metric Serverをデプロイ

```
$ kubectl apply -f ./kind-metric-server.yaml
```

`kubectl top` コマンドで動作確認

```
$ kubectl -n kube-system top pod
NAME                                         CPU(cores)   MEMORY(bytes)
coredns-66bff467f8-996b2                     3m           7Mi
coredns-66bff467f8-zcgdq                     3m           6Mi
etcd-kind-control-plane                      21m          32Mi
kindnet-gdqns                                1m           6Mi
kindnet-lmrjg                                1m           6Mi
kindnet-vqtfk                                1m           6Mi
kube-apiserver-kind-control-plane            40m          328Mi
kube-controller-manager-kind-control-plane   14m          32Mi
kube-proxy-b5285                             1m           10Mi
kube-proxy-rwrsq                             1m           10Mi
kube-proxy-s9h48                             1m           11Mi
kube-scheduler-kind-control-plane            4m           11Mi
metrics-server-5fcb9f447b-vjrc9              1m           13Mi
```

2020/05/27: カスタムメトリクスによるオートスケールの最も簡単な検証
---
いきなりだけど、標準のMetric Serverは使わずにカスタムメトリクスを利用した自動スケールを試す。

[Custom Metrics Adapter Server Boilerplateの手順](https://github.com/kubernetes-sigs/custom-metrics-apiserver#clone-and-build-the-testing-adapter)に従って、テスト用のCustom Metrics API Serverをデプロイする。
`curl -XPOST` のところまで手順を進めると、Custom Metrics API Serverが `300m` という固定値を返すようになっている。


サンプルのDeploymentとHPAをデプロイする。
ここでは `300m` を超えるメトリクス値が観測されると自動スケールが働くように設定されている。
このため、自動スケールはまだ機能しない。

```
$ kubectl apply -f manifests/nginx.yaml
```

`300m` を超える値がMetric Serverから返却されるように設定すると、HPAが動作し始める。 

```
$ curl -XPOST -H 'Content-Type: application/json' http://localhost:80/api/v1/namespaces/custom-metrics/services/custom-metrics-apiserver:http/proxy/write-metrics/namespaces/default/services/kubernetes/test-metric --data-raw '"400m"'
```

（この後、メトリクスを下げただけではスケールダウンが働かなかったので調べる。）



参考リンク集
---

- Kubermetes公式ドキュメント
    - [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
    - [Extending the Kubernetes API with the aggregation layer](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/)
    - [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug-application-cluster/resource-metrics-pipeline/)

- github.com
    - [Repository top](https://github.com/kubernetes/metrics)
    - [Implementations](https://github.com/kubernetes/metrics/blob/master/IMPLEMENTATIONS.md)
    - [Metric Server](https://github.com/kubernetes-sigs/metrics-server)
    - [Design Proposals](https://github.com/kubernetes/community/tree/master/contributors/design-proposals/instrumentation)
    - [Custom Metrics Adapter Server Boilerplate](https://github.com/kubernetes-sigs/custom-metrics-apiserver)

- Kubernetes API Reference
    - [HorizontalPodAutoscaler v2beta2 autoscaling](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.18/#horizontalpodautoscaler-v2beta2-autoscaling)

- ingress-nginx
    - [Prometheus and Grafana installation](https://github.com/kubernetes/ingress-nginx/blob/master/docs/user-guide/monitoring.md)
