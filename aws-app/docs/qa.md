# Q&A

## Q1. なぜFargate起動タイプを使うのか？

EC2起動タイプ（自前でEC2インスタンスをクラスターに登録する方式）と比較して、Fargateはサーバー管理が不要な点が理由です。

| 項目 | EC2起動タイプ | Fargate |
|---|---|---|
| インスタンス管理 | 必要（AMI更新・パッチ適用等） | 不要（AWSが管理） |
| キャパシティプランニング | クラスターのインスタンス数を事前に用意 | タスク単位で自動的に確保される |
| 向いているケース | 大規模・コスト最適化を突き詰めたい場合 | 個人開発・小〜中規模・運用工数を減らしたい場合 |

本テンプレートは運用工数の削減を優先し、Fargateを前提としている。

---

## Q2. ECSタスクがパブリックサブネットに配置されるのはなぜか？

NAT Gatewayのコスト（時間課金 + データ処理料金）を避けるため。

| 構成 | ECSタスクの配置 | NAT Gateway |
|---|---|---|
| 一般的な構成 | プライベートサブネット | 必要（ECR pull・外部通信のため） |
| **本テンプレートの構成** | パブリックサブネット + パブリックIP付与 | **不要** |

ECSタスクにパブリックIPが付与されるが、セキュリティグループで「ALB用SGからのインバウンドのみ許可」としているため、外部から直接アクセスされることはない（[詳細 → docs/design.md](design.md) 4-2節）。

---

## Q3. Blue/Greenデプロイの本番リスナー(:80)とテストリスナー(:8080)は何のためにあるか？

CodeDeployがECS Blue/Greenデプロイを行う際の「新旧切り替え」と「切り替え前の動作確認」に使う。

| リスナー | ポート | 役割 |
|---|---|---|
| 本番リスナー | 80 | 実際のユーザートラフィックが流れる。デプロイ前はBlue、デプロイ完了後はGreenに向く |
| テストリスナー | 8080 | デプロイ中、新バージョン(Green)に対して本番トラフィックを流す前に動作確認するための入口 |

デプロイが成功すると本番リスナーの向き先がBlue→Greenに切り替わり、5分後に旧環境(Blue)のタスクが終了する。

---

## Q4. オートスケーリングの設定を変更するにはどうすればいいか？

`terraform.tfvars`（Terraform版）または `--parameter-overrides`（CloudFormation版）で以下のパラメータを変更する。

| パラメータ名 | 説明 | デフォルト |
|---|---|---|
| `autoscaling_min_capacity` / `AutoscalingMinCapacity` | タスク数の最小値 | 1 |
| `autoscaling_max_capacity` / `AutoscalingMaxCapacity` | タスク数の最大値 | 4 |
| `autoscaling_cpu_target_value` / `AutoscalingCpuTargetValue` | CPU使用率の目標値(%)。この値を超えるとスケールアウトする | 70 |

設定場所の詳細は [docs/design.md](design.md) の「インターフェース定義」を参照。CPU使用率以外の指標（ALBリクエスト数等）でスケールしたい場合は `resource_design.md` の Application Auto Scaling セクションを参考にポリシーを追加する。

> **CloudFormation運用時の注意**: Terraform版は`lifecycle.ignore_changes`で`desired_count`の変更を無視する設定になっているが、CloudFormation版にはこの仕組みがない。オートスケーリングが稼働した後に`DesiredCount`を指定して再デプロイすると、スケールアウトされたタスク数が強制的に元の値へ戻される可能性があるため、初回デプロイ後はテンプレートの`DesiredCount`を変更する再デプロイを避けること。

---

## Q5. タスクのCPU/メモリサイズを変更するにはどうすればいいか？

現在CPU(256)・メモリ(512)は `aws-app/terraform/modules/ecs/main.tf`（Terraform版）または `aws-app/cloudformation/stacks/03-ecs.yaml`（CloudFormation版）に直接記載されており、IaCの入力パラメータ化はされていない。変更する場合はコードを直接編集する。

> 頻繁に変更する想定がある場合は、`container_cpu` / `container_memory` のような変数化を検討する。
