---
title: "KubeCon EU 2023 Recap"
emoji: "🦙"
type: "tech"
topics: ["kubernetes", "kubecon"]
published: false
---

これはなに
---

これは、[Kubernetes MeetUp Tokyo #58 - KubeCon EU 2023 Recap](https://k8sjp.connpass.com/event/282273/)向けの発表資料として作成した記事です。
AppleのエンジニアであるIllya Chekrygin([Github](https://github.com/ichekrygin))さんによる、「Distributing and Decentralizing Pod Disruption Budget (PDB)」の発表内容を紹介します。

- [Sched](https://sched.co/1HyVE)
- [発表スライド](https://static.sched.com/hosted_files/kccnceu2023/08/Final%20-%20KubeCon%20%2B%20CloudNativeCon%20EU23%20Optional%20PPT.pdf)
- [YouTubeアーカイブ](https://youtu.be/2IPf_AyKSsU)


イントロダクション
---

![セッションタイトル](/images/dpdb-p01.png)

### 発表の要点まとめ

- Kubernetes標準のPod Disruption Budget(PDB)ではカバーできないユースケースがあって困っていた
    - CassandraクラスターをKubernetes上にデプロイして、PDBで保護したいケース
    - 1つのPodに対して複数のPDBを適用することができない
- Distributed PDBというカスタムリソース&コントローラーを開発して解決した
- クラスターを跨いでPDBを効かせるということも可能でアツい

### このセッションを聴いた個人的なモチベーション

- 普段マルチクラスタなKubernetes環境を運用しており、クラスタを跨いでいい感じにリソースを制御するという技術が気になった（将来役に立つかも）

:::message
（宣伝）
以下の記事で、弊チームとZ Labで開発、運用しているマルチクラスタなプラットフォームをご紹介しています 🙇
- [ヤフーにおけるKubernetesを活用したPlatform Engineeringの取り組み](https://techblog.yahoo.co.jp/entry/2023052230423347/)
:::


セッション解説
---
ここからはセッションの中身をかいつまんで紹介します。

### Pod Disruption Budget(PDB)ってこんなやつ

#### PDBの簡単な復習

![PDB](/images/dpdb-p05.png)

- PDBはNamespce Scopedなリソース
- `{.spec.maxUnavailable}`または`{.spec.minAvailable}`フィールドで、`{.spec.selector}`で選択されたPodのうち同時にevictされてもいい数を指定する
- `{.status}`フィールドから、対象のPod群の現在の状況（正常なPod数、期待される正常なPod数など）が分かる

#### PDBのいいところ、いまいちなところ

![PDBのいいところ、いまいちなところ](/images/dpdb-p07.png)

- PDBのいいところ
    - シンプル
- PDBのいまいちなところ
    - Namespaceを跨いだりとかできない
    - Podの選択方法がラベルだけで、細かい指定が難しい
    - 拡張性に難がある
- PDBの勘弁してほしいところ
    - 1つのPodに複数のPDBをマッチさせることができない（エラーになる）
    - 拡張性に難がある

#### 標準のPDBではカバーできないユースケース

![CassadraクラスターとPDB](/images/dpdb-p08.png)

- Cassandraのクラスターで、Shardのレプリケーション範囲をカバーするPDBを考える
    - 5レプリカのうち3つにShardを複製するとした場合、3/5のPodに対するPDBを5つ用意することになる
    - 1つのPodが、複数のPDBの`{.spec.selector}`からマッチしてしまう → このようなPDBは作成できない

### Federated PDBっていうのを考えてみた

#### Federated PDBの基本アイデア

![Federated PDBの基本アイデア](/images/dpdb-p09.png)

- 1つのDistributed PDBリソースに対して、1つの子PDB
- 指定された他のPDB(Federation PDB)の`{.status}`に応じて、子PDBの`{.spec}`を書き換える
    - Federation PDBは複数でもよい
    - Federation PDBは他のDistributed PDBの子PDBでもよい(Bidirectional)

#### CassandraクラスターとFederated PDB

![CassandraクラスターとFederated PDB](/images/dpdb-p10.png)

- Distributed PDBリソース
    - `{.spec.maxUnavailable}`、`{.spec.minAvailable}`、`{.spec.selector}`に加えて、`{.spec.federation}`がある
    - `{.spec.selector}`1つのPodを選択する（のが基本と思われる）。このPodに対する子PDBが作られる
    - `{.spec.federation}`にFederation PDBとなるPDBリソースを指定する
- Cassandraクラスターのユースケースに適用した場合
    - `{.spec.selector}`を1つのレプリカにマッチさせる
    - Shardの複製先のレプリカ（に対するPDB）をFederation PDBに指定する
    - この図の例では、Distributed PDBを5つapplyし、コントローラーによって子PDBがそれぞれ1つずつ作成される。それぞれのDistributed PDBは他のDPDBの子PDBをFederation PDBとして参照している
    - 1つのレプリカがevictされると、それをFedration PDBとして参照しているPDBのspecを変更して、同じShardがそれ移動evictされないようになる

#### Multi Namespace PDB

![Multi Namespace PDB](/images/dpdb-p11.png)

- Namespaceを跨いでFederation PDBを指定できる。これによってNamespceを跨いで作用するPDBを実現できる

#### Multi Cluster PDB

![Multi Cluster PDB](/images/dpdb-p12.png)

- クラスターを跨いでFederation PDBを指定できる。これによってクラスターを跨いで作用するPDBを実現できる

### デモ
3つのKubernetesにまたがるFederated PDBのデモ。スライドのユースケースよりも少し複雑な構成で、9レプリカで5つにShardが複製されるクラスターになっている。

- ローカルマシン上にkindクラスタx3

```
$ kubeclt config get-contexts
CURRENT   NAME         CLUSTER      AUTHINFO     NAMESPACE
          kind-blue    kind-blue    kind-blue
*         kind-green   kind-green   kind-green
          kind-red     kind-red     kind-red
```

- 9つのレプリカを3クラスタに分散配置

```
$ for i in red blue green; do kubectl --context=kind-$i get pods --show-labels; done
NAME                 READY   STATUS    RESTARTS   AGE     LABELS
database-00-10-20   1/1     Running   0          2m33s   app=database,ring=00-10-20
database-30-40-50   1/1     Running   0          2m32s   app=database,ring=30-40-50
database-60-70-80   1/1     Running   0          2m31s   app=database,ring=60-70-80
NAME                 READY   STATUS    RESTARTS   AGE     LABELS
database-10-20-30   1/1     Running   0          2m32s   app=database,ring=10-20-30
database-40-50-60   1/1     Running   0          2m32s   app=database,ring=40-50-60
database-70-80-00   1/1     Running   0          2m31s   app=database,ring=70-80-00
NAME                 READY   STATUS    RESTARTS   AGE     LABELS
database-20-30-40   1/1     Running   0          2m32s   app=database,ring=20-30-40
database-50-60-70   1/1     Running   0          2m32s   app=database,ring=50-60-70
database-80-00-10   1/1     Running   0          2m31s   app=database,ring=80-00-10
```

- 各Podに対応するPDBが作られている

```
$ for i in red blue green; do kubectl --context=kind-$i get pdb; done
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-00-10-20   4               N/A               1                     26s
database-30-40-50   4               N/A               1                     23s
database-60-70-80   4               N/A               1                     22s
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-10-20-30   4               N/A               1                     25s
database-40-50-60   4               N/A               1                     22s
database-70-80-00   4               N/A               1                     22s
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-20-30-40   4               N/A               1                     23s
database-50-60-70   4               N/A               1                     22s
database-80-00-10   4               N/A               1                     22s
```

- Podをひとつevictすると、Shardが複製されている他のPodのPDBが`allowedDisruptions=0`となり、それ以上Evictされないようになる

```
$ for i in red blue green; do kubectl --context=kind-$i get pdb; done
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-00-10-20   4               N/A               1                     3m13s
database-30-40-50   4               N/A               0                     3m10s <-- evicted pod
database-60-70-80   4               N/A               1                     3m9s
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-10-20-30   4               N/A               0                     3m12s
database-40-50-60   4               N/A               0                     3m9s
database-70-80-00   4               N/A               1                     3m9s
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
database-20-30-40   4               N/A               0                     3m10s
database-50-60-70   4               N/A               0                     3m9s
database-80-00-10   4               N/A               1                     3m9s
```


所感
---

- 1つのPodのevictが他のPDBに伝搬するのにタイムラグがあり、これが実用上どの程度問題になるかが気になった
- コントローラーが複数クラスタに1つずつ配置されて協調動作する、という構成をシンプルな仕組みで実現していて面白い（1つのクラスタにコントローラーがいて、他クラスタのリソースをコントロールするのではない）
- 全体としての挙動が予想しづらい印象を持ったがどうなのか


以上。
