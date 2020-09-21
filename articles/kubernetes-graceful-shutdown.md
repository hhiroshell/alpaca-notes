---
title: "アルパカでもわかる安全なPodの終了"
emoji: "🦙"
type: "tech"
topics: ["kubernetes"]
published: false
---

これはなに
---
KubernetesにおいてPodが終了するまでの動作を整理し、それを踏まえて、安全な（リクエストの欠損を極小化した）オンラインのローリングアップデートを実現するためにどうすればいいかを考察します。

<!-- ### 想定する前提知識

- 突き合わせループの概念を理解している
- KubernetesのDeployment, Service, Podリソースを使ったことがある -->

TD;LR
---


目次
---

- イントロダクション
- Podが終了する過程
- 安全なPodの終了のために注意すべきこと


イントロダクション
---
Podが終了するまでの動作は、@superbrothersさんによる[詳解 Pods の終了](https://qiita.com/superbrothers/items/3ac78daba3560ea406b2)に詳しくまとめられています。
数年前の記事にはなりますが、[公式ドキュメント]()を見たところ今でもそのまま当てはまると考えて良さそうです。

<!-- というわけでこの章は「そちらをご覧ください！」で終わってもよいのですが、それではあまりにも身も蓋もないので、ここでは「これはなに」にある目標を達成するために必要な情報に絞って整理したいと思います。 -->

Podが終了する過程
---
コンテナイメージの更新や `kubectl delete pod` の実行など、Podの終了のトリガーとなる事象が起きると、それまで起動していたPodに対する終了処理が開始されます。
Podの終了処理の全体の流れは以下のとおりです。

1. Podの終了予定時刻をPodリソースに設定する
2. Podリソースをウォッチする複数のコンポーネントが、それぞれの終了処理を実行する
    - 2-a. kubeletによるプロセスのシャットダウン
    - 2-b. endpoints controllerとkube-proxyによるサービスアウト
    - 2-c. Ownerリソースによる管理からの除外

2.の3つの処理は、それぞれを担当するコンポーネントが独立して実行するため、例えば「サービスアウトしてからシャットダウンする」といったような互いに依存関係を持った制御は行われません。
これは、本エントリーのテーマのひとつである、「Podの安全な終了」を考える上で重要なポイントになりますので、注意してください。

<!-- TODO: 図 -->

以降は、上に挙げた各処理において具体的にどのような処理が行われているかを説明します。

### 1 . Podの終了予定時刻をPodリソースに設定する
削除対象しようとしているPodに対応するPodリソースに対して、 `.metadata.deletionTimestamp` と `.metadata.deletionGracePeriodSeconds` が設定されます。

- `.metadata.deletionTimestamp` :
    - 削除予定時刻。このフィールドの設定が行われる時刻に `.spec.terminationGracePeriodSeconds` （デフォルト: 30秒）を加算した値が設定される
- `.metadata.deletionGracePeriodSeconds` : 
    - このフィールドの設定が行われる時点での `.spec.terminationGracePeriodSeconds` の値が設定される

これをきっかけに、Podリソースをウォッチしている各コンポーネントが後続の終了処理を開始します。

### 2-a. kubeletによるプロセスのシャットダウン
Podリソースに `.metadata.deletionTimestamp` が設定されたことをkubeletが検知すると、kubeletは以下のシャットダウンプロセスを開始します。

- 2-a-1. preStopフックを実行する
- 2-a-2. Dockerデーモンにコンテナの終了を依頼する

preStopフックは、プロセスの終了前に実行する事前処理です。
`.spec.containers[].lifecycle.preStop` に処理内容を記述することができます。
指定可能な処理は、任意のコマンドの実行、所定のエンドポイントへのHTTP GETリクエスト、TCPソケットのオープンの試行、の3種です。

preSropフックが終了するか、 `.metadata.deletionGracePeriodSeconds` の時間が経過した場合、kubeletがDockerデーモンにコンテナの終了を依頼します。[^1], [^2]
このとき、終了処理のタイムアウト時間として、以下の値が渡されます。

- preStopフックが `.metadata.deletionGracePeriodSeconds` までに終了した場合:
    - `.metadata.deletionGracePeriodSeconds` からpreStopフックの所要時間で引いた値（2秒以下だった場合は2秒に切り上げ）
- preStopフックが `.metadata.deletionGracePeriodSeconds` までに終了しなかった場合
    - 2秒:

コンテナの終了処理では、始めにコンテナにSIGTERMシグナルが送信されます。
多くのアプリケーションでは、SIGTERMの受信を受けて終了処理を開始するように実装することが多いと思います(Gracefl Shutdown)。

SIGTERMの後、タイムアウト時間が経過してもコンテナが終了していない場合、SIGKILLシグナルが送信されます。
ここで、コンテナが強制的にシャットダウンされます。

[^1]: https://github.com/kubernetes/kubernetes/blob/v1.18.9/pkg/kubelet/kuberuntime/kuberuntime_container.go#L544-L550
[^2]: https://github.com/kubernetes/kubernetes/blob/v1.18.9/pkg/kubelet/kuberuntime/kuberuntime_container.go#L635-L650

#### シャットダウン処理の時系列
シャットダウン処理の時系列と `.metadata.deletionGracePeriodSeconds` の関係を図に起こしてみると、以下のようになります。

##### preStopフックが `.metadata.deletionGracePeriodSeconds` までに終了した場合

<!-- 図 -->

##### preStopフックが `.metadata.deletionGracePeriodSeconds` までに終了しなかった場合

<!-- 図 -->

### 2-b. endpoints controllerとkube-proxyによるサービスアウト
Podリソースに `deletionTimestamp` が設定されたことをendpoints controllerが検知すると、対象のPodにルーティングするように設定されているServiceリソースから、Podのendpointを除外します。
さらに、Serviceリソースからendpointが除外されると、kube-proxyがNodeのiptableを更新します。
これによってPodに対して新規TCPコネクションが作成されないようになります（サービスアウト）。

<!-- 図 -->

### 2-c. Ownerリソースによる管理からの除外
Ownerリソースは、あるリソースに対してそれを管理する関係にある上位のリソースです。Podリソースの場合、ReplicaSet、DaemonSetなどが該当します。
ReplicaSetやDaemonSet、はたまたReplicaSetの更にOwnerリソースとなるDeploymentなどを `kubectl create` することでPodを起動している場合、そのPodはOwnerの管理下にあります。

<!-- 図 -->

Podリソースに `deletionTimestamp` が設定されたことをOwnderリソースのcontrollerが検知すると、Ownerリソースの管理下からPodが除外されます。

#### Deploymentを起点にPodを起動している場合
ここでは、Deploymentを起点にPodを起動している場合の動作を見てみます。


安全なPodの終了のために注意すべきこと
---
改めてPodが終了するまでの過程を時系列に整理すると、以下のようになります。
