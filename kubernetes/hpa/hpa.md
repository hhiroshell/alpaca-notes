アルパカでもわかる Horizontal Pod Autoscaler
===

【参考】KindクラスターにMetric Serverを導入する
---
KindクラスターにMetric Serverを導入する手順を記す

まず、kindを使って3ノードクラスターを作成する

```
$ kind create cluster --config ./kind-cluster-config.yaml
```

Metric Serverをデプロイする

```
$ kubectl apply -f ./kind-metric-server.yaml
```

`kubectl top` コマンドを実行してMetric Serverが機能していることを確認する

```
$ kubectl -n kube-system top pod
NAME                                         CPU(cores)   MEMORY(bytes)
coredns-66bff467f8-996b2                     3m           7Mi
coredns-66bff467f8-zcgdq                     3m           6Mi
etcd-kind-control-plane                      21m          32Mi
(...snip...)
```

<br>

カスタムメトリクスによるオートスケールの検証
---
[Custom Metrics Adapter Server Boilerplateの手順](https://github.com/kubernetes-sigs/custom-metrics-apiserver#clone-and-build-the-testing-adapter)に従って、カスタムメトリクスを利用した自動スケールを試す。

まずは上記手順に従ってCustom Metrics API Serverをセットアップする。
`curl -X POST` のところまで手順を進めると、Custom Metrics API Serverが `300m` という固定値を返すようになっている。

このCustom Metrics API Serverは、専用のEndpointにPOSTリクエストを送ることによって返却される固定値を設定することができる。
以下は、`default` ネームスペースの `kubernetes` という名前のServiceに、 `test-metric=300m` という値を設定しているところ。

```
$ curl -X POST -H 'Content-Type: application/json' http://localhost:8001/api/v1/namespaces/custom-metrics/services/custom-metrics-apiserver:http/proxy/write-metrics/namespaces/default/services/kubernetes/test-metric --data-raw '"300m"'
```

このように設定したメトリクスは、API Serverからアクセス可能なリソースとして取得することができる。

```
$ curl http://localhost:8001/apis/custom.metrics.k8s.io/v1beta2/namespaces/default/services/kubernetes/test-metric
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta2",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta2/namespaces/default/services/kubernetes/test-metric"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Service",
        "namespace": "default",
        "name": "kubernetes",
        "apiVersion": "/v1"
      },
      "metric": {
        "name": "test-metric",
        "selector": null
      },
      "timestamp": "2020-05-27T17:36:07Z",
      "value": "300m"
    }
  ]
}
```

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

<br>

HPA関連のKubernetesリソースを読解してみる
---

```
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-deployment
  namespace: default
spec:
  scaleTargetRef:               ...1
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment
  minReplicas: 1
  maxReplicas: 10
  metrics:                      ...2
  - type: Object                ...3
    object:
      metric:
        name: test-metric
      describedObject:
        apiVersion: v1
        kind: Service
        name: kubernetes
      target:
        type: Value
        value: 300m
```

| # | 説明
| - | -
| 1 |スケールさせる対象のオブジェクトを特定するフィールド。PodsMetricを使ったオートスケールを行う場合、メトリクスを収集する対象のPodを特定するためにも使われる
| 2 |収集するメトリクスと、スケーリングの閾値の定義
| 3 |メトリクス種別（下記参照）

### メトリクス種別

- Resource:
    - スケールさせる対象の各PodでResource Limits/Requestsに指定されたメトリクス
    - `Pods` を使った方法よりも特殊なスケーリング判定ロジックを利用することができる
- Pods: 
    - Podから収集されるメトリクス
    - メトリクス収集のエンドポイントをPodに作成して、それを利用することが可能
    - 対象のPod群の平均値が閾値との比較に使われる
- Object: 
    - Kubernetesオブジェクトに紐付いたメトリクス（例: あるIngressリソース）
    - メトリクスの値は、API Serverの特定のKubernetesオブジェクトに紐付いたパスを叩くことで取得する
    - 実際の値は、Aggregation Layerを使って呼び出されるWebhookから取得される（このWebhookを用意しておく必要がある）
- External:
    - Kubernetesオブジェクトと関連しないメトリクスソース
    - 実際の値は、Aggregation Layerを使って呼び出されるWebhookから取得される（このWebhookを用意しておく必要がある）

### Aggregation Layerについての補足
API Server経由で自作のCustom Metrics API Serverにアクセスさせるには、Aggregation Layerという機能を利用する。
Aggregation Layerでは、APIServiceというリソースによって使いたいCustom Metrics API Serverを登録する。

```
apiVersion: apiregistration.k8s.io/v1beta1
kind: APIService
metadata:
  name: v1beta1.custom.metrics.k8s.io
spec:
  service:
    name: custom-metrics-apiserver
    namespace: custom-metrics
  group: custom.metrics.k8s.io
  version: v1beta1
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 100
---
apiVersion: apiregistration.k8s.io/v1beta1
kind: APIService
metadata:
  name: v1beta2.custom.metrics.k8s.io
spec:
  service:
    name: custom-metrics-apiserver
    namespace: custom-metrics
  group: custom.metrics.k8s.io
  version: v1beta2
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 200
```

上記のようなリソースを `apply` することにより、新たなKubernetesリソースとして、Custom Metrics API Serverにアクセスすることができる。

```
curl http://localhost:8001/apis/custom.metrics.k8s.io/v1beta2/
{
  "kind": "APIResourceList",
  "apiVersion": "v1",
  "groupVersion": "custom.metrics.k8s.io/v1beta2",
  "resources": [
    {
      "name": "services/test-metric",
      "singularName": "",
      "namespaced": true,
      "kind": "MetricValueList",
      "verbs": [
        "get"
      ]
    }
  ]
}
```

<br>

参考リンク集
---

- Kubermetes公式ドキュメント
    - [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
    - [Extending the Kubernetes API with the aggregation layer](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/)
    - [Configure the Aggregation Layer](https://kubernetes.io/docs/tasks/access-kubernetes-api/configure-aggregation-layer)
    - [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug-application-cluster/resource-metrics-pipeline/)
    - [The Kubernetes API](https://kubernetes.io/docs/concepts/overview/kubernetes-api/)

- github.com
    - [Repository top](https://github.com/kubernetes/metrics)
    - [Implementations](https://github.com/kubernetes/metrics/blob/master/IMPLEMENTATIONS.md)
    - [Metric Server](https://github.com/kubernetes-sigs/metrics-server)
    - [Design Proposals](https://github.com/kubernetes/community/tree/master/contributors/design-proposals/instrumentation)
    - [Custom Metrics Adapter Server Boilerplate](https://github.com/kubernetes-sigs/custom-metrics-apiserver)
    - [Use an HTTP Proxy to Access the Kubernetes API](https://kubernetes.io/docs/tasks/access-kubernetes-api/http-proxy-access-api/)

- Kubernetes API Reference
    - [HorizontalPodAutoscaler v2beta2 autoscaling](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.18/#horizontalpodautoscaler-v2beta2-autoscaling)

- ingress-nginx
    - [Prometheus and Grafana installation](https://github.com/kubernetes/ingress-nginx/blob/master/docs/user-guide/monitoring.md)

- サードパーティのドキュメント
    - [Datadog Document: Custom Metrics Server](https://docs.datadoghq.com/ja/agent/cluster_agent/external_metrics/)
    - [Datadog Agentのhpa設定](https://github.com/DataDog/datadog-agent/blob/master/Dockerfiles/manifests/cluster-agent/hpa-example/rbac-hpa.yaml)