---
title: "Pod内に複数のコンテナがある場合の起動シーケンス"
emoji: "🦙"
type: "tech"
topics: ["kubernetes"]
published: true
---

これはなに
---
「Kubernetesマイクロサービス開発の実践」というKubernetes本を執筆しまして、めでたく先日発売となりました！ぜひ買ってくださいー。

- 「[Kubernetesマイクロサービス開発の実践](https://www.amazon.co.jp/dp/4295018147/)」

この書籍の第7章には、PodオブジェクトがAPI Serverに作成されてから実際にPodが起動するまでの処理を解説した箇所があるのですが、諸事情のため書籍では載せられなかったマニアックな挙動があります。それは、Podに複数のコンテナがあり、いずれかまたはすべてのコンテナでpostStart Lifecycle Hookを使っている場合です。このエントリーではそのようなPodが起動するとき、どのような動作になるかを書きます。

> 📘【note】
> これは[Kubernetes Advent Calendar 2023](https://qiita.com/advent-calendar/2023/kubernetes)の20日目の記事です。


お題のPod
---
本記事では、以下のマニフェストのような複数のコンテナ(container1, container2)を含むPodを使って実験します。ちょっと長いですが、やっていることは以下のような感じです。

- container1はメインの処理、postStartフック、Readines Probe、Liveness Probeで、それぞれ1秒おきに `/var/log/startup-sequence-test/message` にログを出力する
- container2はメインの処理で、1秒おきに、上と同じファイルにログを出力する

```yaml:startup-sequence-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: startup-sequence-test
  namespace: default
spec:
  containers:
  - name: container1
    image: busybox:latest
    args:
    - /bin/sh
    - -c
    - |
      for i in $(seq 60); do
        echo "$(date): container1 / main" >> /var/log/startup-sequence-test/message
        sleep 1
      done
      tail -f /dev/null
    lifecycle:
      postStart:
        exec:
          command:
          - "/bin/sh"
          - "-c"
          - |
            for i in $(seq 30); do
              echo "$(date): container1 / post start hook" >> /var/log/startup-sequence-test/message
              sleep 1
            done
    readinessProbe:
      exec:
        command:
        - "/bin/sh"
        - "-c"
        - |
          echo "$(date): container1 / readiness probe" >> /var/log/startup-sequence-test/message
    livenessProbe:
      exec:
        command:
        - "/bin/sh"
        - "-c"
        - |
          echo "$(date): container1 / liveness probe" >> /var/log/startup-sequence-test/message
    volumeMounts:
    - mountPath: /var/log/startup-sequence-test
      name: log-volume
  - name: container2
    image: busybox:latest
    args:
    - /bin/sh
    - -c
    - |
      for i in $(seq 60); do
        echo "$(date): container2 / main" >> /var/log/startup-sequence-test/message
        sleep 1
      done
      tail -f /dev/null
    volumeMounts:
    - mountPath: /var/log/startup-sequence-test
      name: log-volume
  volumes:
  - name: log-volume
    emptyDir: {}
```

このPodをクラスタに適用した後、`/var/log/startup-sequence-test/message` に書かれている内容を確認すれば、それぞれの処理がどのような順番で実行されているかが分かるというわけです。


期待する挙動
---
実験してみる前にどのような動作になるか予想してみましょう。おおよそ以下のような感じになるでしょうか...？

1. container1、container2のメインの処理が開始される（Pod内のコンテナの起動順序には依存関係はなさそうに思える）
2. container1のメインの処理が開始された直後に、postStartフックが開始される
3. 2. が終了するとReadiness Probe、Liveness Probeが開始される

この予想を図にすると以下のようになります。2つのコンテナが同時に起動を始めるような形です。

![pod-startup-sequence-1](https://raw.githubusercontent.com/hhiroshell/alpaca-notes/master/articles/images/pod-startup-sequence-1.png)


実験してみた
---
それでは、実際にクラスタに適用して起動するまでの様子を見てみましょー。

```console
$ kubectl apply -f startup-sequence-test.yaml && kubectl get pod startup-sequence-test -w
pod/startup-sequence-test created
NAME                    READY   STATUS              RESTARTS   AGE
startup-sequence-test   0/2     ContainerCreating   0          0s
startup-sequence-test   1/2     Running             0          37s  <-- 2つのコンテナうちの片方がREADYに
startup-sequence-test   2/2     Running             0          37s  <-- 残りのコンテナがREADYに
```

上の`kubectl get pod`の結果を見ると、既に予想に反していそうな雰囲気があります。それは、2つのコンテナのどちらも、READYになるまでに37sかかっていることです。postStartフックやProbeを設定していないcontainer2については、コンテナが起動すればすぐにREADYになるはずですが…。

次にログの出力結果を見てみましょう。

```console
$ kubectl exec startup-sequence-test -- cat /var/log/startup-sequence-test/message
Defaulted container "container1" out of: container1, container2
Thu Dec 21 10:40:51 UTC 2023: container1 / main
Thu Dec 21 10:40:51 UTC 2023: container1 / post start hook
Thu Dec 21 10:40:52 UTC 2023: container1 / main
Thu Dec 21 10:40:52 UTC 2023: container1 / post start hook
Thu Dec 21 10:40:53 UTC 2023: container1 / main
Thu Dec 21 10:40:53 UTC 2023: container1 / post start hook
...(約30秒)...
Thu Dec 21 10:41:21 UTC 2023: container1 / main
Thu Dec 21 10:41:22 UTC 2023: container1 / main
Thu Dec 21 10:41:23 UTC 2023: container2 / main
Thu Dec 21 10:41:23 UTC 2023: container1 / main
Thu Dec 21 10:41:23 UTC 2023: container1 / readiness probe
Thu Dec 21 10:41:23 UTC 2023: container1 / liveness probe
Thu Dec 21 10:41:23 UTC 2023: container1 / readiness probe
Thu Dec 21 10:41:24 UTC 2023: container2 / main
Thu Dec 21 10:41:24 UTC 2023: container1 / main
Thu Dec 21 10:41:24 UTC 2023: container1 / liveness probe
Thu Dec 21 10:41:24 UTC 2023: container1 / readiness probe
...
```

というわけで、container1とcontainer2のメイン処理はほぼ同時に開始されるという予想でしたが、どうやらcontainer1のpostStartフックが終了するまでcontainer2は開始されないようです。前述の予想の1.が外れた結果となりました。

この結果から、container2の動作の開始はcontainer1のpostStartフックの終了に依存していることになりますが、ではこの依存関係はどうやって決まっているのでしょうか。すぐに思いつくのは、Podリソースでコンテナを記述する順序です。


実験2
---
Podリソースにおけるコンテナの順序と、起動時の依存関係を確かめるために、container1とcontainer2の記述順序を逆にして実験をしてみます。マニフェストファイルは以下のとおりです。

```yaml:startup-sequence-test-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: startup-sequence-test
  namespace: default
spec:
  containers:
  - name: container2
    # ... 順番を入れ替えただけで内容は同じ
  - name: container1
    # ... 順番を入れ替えただけで内容は同じ
  volumes:
  - name: log-volume
    emptyDir: {}
```

同じようにクラスタに適用して、`kubectl get`とログの内容を確認してみます。

```console
$ kubectl apply -f startup-sequence-test-2.yaml && kubectl get pod startup-sequence-test -w
pod/startup-sequence-test created
NAME                    READY   STATUS              RESTARTS   AGE
startup-sequence-test   0/2     ContainerCreating   0          0s
startup-sequence-test   1/2     Running             0          35s  <-- 2つのコンテナうちの片方がREADYに
startup-sequence-test   2/2     Running             0          35s  <-- 残りのコンテナがREADYに

$ kubectl exec startup-sequence-test -- cat /var/log/startup-sequence-test/message
Defaulted container "container2" out of: container2, container1
Thu Dec 21 12:17:07 UTC 2023: container2 / main
Thu Dec 21 12:17:08 UTC 2023: container2 / main
Thu Dec 21 12:17:08 UTC 2023: container1 / main
Thu Dec 21 12:17:08 UTC 2023: container1 / post start hook
Thu Dec 21 12:17:09 UTC 2023: container2 / main
Thu Dec 21 12:17:09 UTC 2023: container1 / main
Thu Dec 21 12:17:09 UTC 2023: container1 / post start hook
Thu Dec 21 12:17:10 UTC 2023: container2 / main
Thu Dec 21 12:17:10 UTC 2023: container1 / main
Thu Dec 21 12:17:10 UTC 2023: container1 / post start hook
...(約30秒)...
Thu Dec 21 12:17:38 UTC 2023: container2 / main
Thu Dec 21 12:17:38 UTC 2023: container1 / main
Thu Dec 21 12:17:39 UTC 2023: container2 / main
Thu Dec 21 12:17:39 UTC 2023: container1 / readiness probe
Thu Dec 21 12:17:39 UTC 2023: container1 / main
Thu Dec 21 12:17:40 UTC 2023: container2 / main
Thu Dec 21 12:17:40 UTC 2023: container1 / readiness probe
Thu Dec 21 12:17:40 UTC 2023: container1 / liveness probe
Thu Dec 21 12:17:40 UTC 2023: container1 / main
Thu Dec 21 12:17:41 UTC 2023: container2 / main
Thu Dec 21 12:17:41 UTC 2023: container1 / readiness probe
Thu Dec 21 12:17:41 UTC 2023: container1 / liveness probe
...
```

コンテナがREADYになるタイミングは、最初の実験と同様container1のpostStartフックが終了してからのようです。ただし、ログを見る限りcontainer2の処理はすぐに開始されており、続いてcontainer1のメインの処理とpostStartフックが始まっています。こちらの場合は、container2がcontainer1のpostStartフックを待っている様子はありません。

というわけで、Podに複数のコンテナがある場合の起動順序は、以下のようになるものと考えられます。

- マニフェストに記述した順にコンテナの起動が行われる
- postStartフックが設定されている場合、その処理が終了してから次のコンテナの起動が開始される

図に表すと、以下のような感じです。

![pod-startup-sequence-2](https://raw.githubusercontent.com/hhiroshell/alpaca-notes/master/articles/images/pod-startup-sequence-2.png)


実装を見てみる
---
実験の結果からは上述のような起動順序であると考えられますが、実際にそうなっているのかコードでも確認してみましょう。Podの起動を担っているのはkubeletというコンポーネントなので、kubeletのコードから該当箇所を探って行きます。

まず、コンテナの起動を指示する `start()` という処理を呼び出しているのがこちら。

- https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/kuberuntime/kuberuntime_manager.go#L1316-L1318

```go
	for _, idx := range podContainerChanges.ContainersToStart {
		start(ctx, "container", metrics.Container, containerStartSpec(&pod.Spec.Containers[idx]))
	}
```

Podに記述された複数のコンテナでループして、直列に`start()`を呼び出していることが分かります。

次に、`start()`の中身がこちら。

- https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/kuberuntime/kuberuntime_manager.go#L1231-L1268

```go
	start := func(ctx context.Context, typeName, metricLabel string, spec *startSpec) error {
		# ...(snip)...

		if msg, err := m.startContainer(ctx, podSandboxID, podSandboxConfig, spec, pod, podStatus, pullSecrets, podIP, podIPs); err != nil {
			# ...(snip)...

			return err
		}

		return nil
	}
```

`start()`から、さらに`m.startContainer()`を呼び出します。

`m.startContainer()` の内部の処理は以下のようになっています。

- https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/kuberuntime/kuberuntime_container.go#L269-L314

```go
func (m *kubeGenericRuntimeManager) startContainer(ctx context.Context, podSandboxID string, podSandboxConfig *runtimeapi.PodSandboxConfig, spec *startSpec, pod *v1.Pod, podStatus *kubecontainer.PodStatus, pullSecrets []v1.Secret, podIP string, podIPs []string) (string, error) {
	container := spec.container

	// Step 1: pull the image.
	...(snip)...

	// Step 2: create the container.
	// For a new container, the RestartCount should be 0
	...(snip)...

	// Step 3: start the container.
	err = m.runtimeService.StartContainer(ctx, containerID)
	...(snip)...

	// Step 4: execute the post start hook.
	if container.Lifecycle != nil && container.Lifecycle.PostStart != nil {
		kubeContainerID := kubecontainer.ContainerID{
			Type: m.runtimeName,
			ID:   containerID,
		}
		msg, handlerErr := m.runner.Run(ctx, kubeContainerID, pod, container, container.Lifecycle.PostStart)
		if handlerErr != nil {
			klog.ErrorS(handlerErr, "Failed to execute PostStartHook", "pod", klog.KObj(pod),
				"podUID", pod.UID, "containerName", container.Name, "containerID", kubeContainerID.String())
			// do not record the message in the event so that secrets won't leak from the server.
			m.recordContainerEvent(pod, container, kubeContainerID.ID, v1.EventTypeWarning, events.FailedPostStartHook, "PostStartHook failed")
			if err := m.killContainer(ctx, pod, kubeContainerID, container.Name, "FailedPostStartHook", reasonFailedPostStartHook, nil, nil); err != nil {
				klog.ErrorS(err, "Failed to kill container", "pod", klog.KObj(pod),
					"podUID", pod.UID, "containerName", container.Name, "containerID", kubeContainerID.String())
			}
			return msg, ErrPostStartHook
		}
	}

	return "", nil
}

```

`Step 4`と示されている箇所でpostStartフックを実行し、処理結果が返ってくるまで待機しているように見えます。postStartフックの処理が非同期なものならすぐにStep 4を抜けて後続の処理に進みそうですが、そうでなければここで待ちになるのではないでしょうか。すると、最初に示したコードの後続のループ処理、つまり次のコンテナの起動処理に進みません。
これが、postStartフックが終了してからコンテナの起動が始まるという動作につながっているようです。


まとめ
---
というわけで、Podに複数のコンテナを記述していてpostStartフックを使用している場合は、起動順序に注意しましょう！

> 🙏【謝辞】
> 本エントリーは、業務の中で社内のKubernetesユーザーからいただいた質問と、それに対するチームメンバーの調査が元ネタになっています。
> この場を借りて、深く感謝申し上げます。


以上です。
最後まで読んでいただきありがとうございました。メリークリスマス！
