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
まずはPDBの簡単な復習。

![PDB](/images/dpdb-p05.png)

- PDBはNamespce Scopedなリソース
- `{.spec.maxUnavailable}`または`{.spec.minAvailable}`フィールドで、`{.spec.selector}`で選択されたPodのうち同時にevictされてもいい数を指定する
- `{.status}`フィールドから、対象のPod群の現在の状況（正常なPod数、期待される正常なPod数など）が分かる

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

### 標準のPDBではカバーできないユースケース

![CassadraクラスターとPDB](/images/dpdb-p08.png)

- Cassandraのクラスターで、Shardのレプリケーション範囲をカバーするPDBを考える
    - 5レプリカのうち3つにShardを複製するとした場合、3/5のPodに対するPDBを5つ用意することになる
    - 1つのPodが、複数のPDBの`{.spec.selector}`からマッチしてしまう → このようなPDBは作成できない

### Federated PDBっていうのを考えてみた

![Federated PDBの基本アイデア](/images/dpdb-p09.png)

- 1つのDistributed PDBリソースに対して、1つの子PDB
- 指定された他のPDB(Federation PDB)の`{.status}`に応じて、子PDBの`{.spec}`を書き換える
    - Federation PDBは複数でもよい
    - Federation PDBは他のDistributed PDBの子PDBでもよい(Bidirectional)

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

![](/images/dpdb-p11.png)
![](/images/dpdb-p12.png)



### 実装はこんな感じになってた





### 所感







まとめ
---







おまけ
---
