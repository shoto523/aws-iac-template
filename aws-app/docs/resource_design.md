# リソース詳細設計書（aws-app）

Terraform の実装コードから起こしたリソース仕様。`${project_name}` はユーザーが `terraform.tfvars` で設定する値。

---

## IAM

### ECS Task Execution ロール

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-ecs-task-execution-role` |
| 信頼するサービス | `ecs-tasks.amazonaws.com` |

#### アタッチされるポリシー

| 対象 | 許可アクション |
|---|---|
| ECR（認証） | ecr:GetAuthorizationToken |
| ECR（イメージ取得） | BatchGetImage, GetDownloadUrlForLayer, BatchCheckLayerAvailability |
| CloudWatch Logs | CreateLogGroup, CreateLogStream, PutLogEvents |

### ECS Task ロール

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-ecs-task-role` |
| 信頼するサービス | `ecs-tasks.amazonaws.com` |
| ポリシー | アプリ要件に応じて追加（初期は空） |

### CodeDeploy 実行ロール

| 項目 | 値 |
|---|---|
| ロール名 | `${project_name}-codedeploy-role` |
| 信頼するサービス | `codedeploy.amazonaws.com` |

#### アタッチされるポリシー

| 対象 | 許可アクション |
|---|---|
| ECS | DescribeServices, UpdateService, RegisterTaskDefinition 他 |
| ALB | DescribeTargetGroups, ModifyListener, ModifyRule 他 |
| IAM | PassRole（ECSタスクロールを渡すため） |
| S3（アーティファクトバケット） | GetObject |

---

## ALB

### aws_lb

| 項目 | 値 |
|---|---|
| ALB名 | `${project_name}-alb` |
| タイプ | application |
| 配置サブネット | `${public_subnet_ids}`（入力パラメータ） |
| セキュリティグループ | `${alb_security_group_id}`（入力パラメータ） |
| 内部/外部 | internet-facing |

### aws_lb_target_group（Blue）

| 項目 | 値 |
|---|---|
| ターゲットグループ名 | `${project_name}-tg-blue` |
| ターゲットタイプ | ip（Fargate使用のため） |
| プロトコル | HTTP |
| ポート | `${container_port}` |
| VPC | `${vpc_id}` |

### aws_lb_target_group（Green）

| 項目 | 値 |
|---|---|
| ターゲットグループ名 | `${project_name}-tg-green` |
| ターゲットタイプ | ip |
| プロトコル | HTTP |
| ポート | `${container_port}` |
| VPC | `${vpc_id}` |

### aws_lb_listener（本番 :80）

| 項目 | 値 |
|---|---|
| ポート | 80 |
| プロトコル | HTTP |
| デフォルトアクション | forward → Blue ターゲットグループ |

### aws_lb_listener（テスト :8080）

| 項目 | 値 |
|---|---|
| ポート | 8080 |
| プロトコル | HTTP |
| デフォルトアクション | forward → Green ターゲットグループ |

---

## ECS

### aws_ecs_cluster

| 項目 | 値 |
|---|---|
| クラスター名 | `${project_name}-cluster` |

### aws_ecs_task_definition

| 項目 | 値 |
|---|---|
| ファミリー名 | `${project_name}` |
| ネットワークモード | awsvpc |
| 起動タイプ互換性 | FARGATE |
| CPU | 256 |
| メモリ | 512 |
| Task Execution Role | ECS Task Execution ロール |
| Task Role | ECS Task ロール |
| コンテナ名 | `${container_name}` |
| コンテナポート | `${container_port}` |
| イメージ | `${ecr_repository_url}:latest`（初回デプロイ時） |
| ログドライバー | awslogs（ロググループ: `/ecs/${project_name}`） |

### aws_ecs_service

| 項目 | 値 |
|---|---|
| サービス名 | `${project_name}-service` |
| クラスター | `${project_name}-cluster` |
| 起動タイプ | FARGATE |
| デプロイコントローラー | CODE_DEPLOY（Blue/Green用） |
| 希望タスク数 | 1（オートスケーリングにより実行時は変動する。[詳細 → Application Auto Scaling](#application-auto-scaling)） |
| サブネット | `${public_subnet_ids}`（ALBと同じパブリックサブネット） |
| セキュリティグループ | `${ecs_security_group_id}` |
| パブリックIP割り当て | 有効（NAT Gateway を使わない構成のため） |
| ロードバランサー | Blue ターゲットグループ |
| ライフサイクル | `task_definition` / `load_balancer` の変更を無視（CodeDeploy が管理するため） |

---

## Application Auto Scaling

ECS Service の `desired_count` を負荷に応じて自動調整する。トラフィックスパイク(急激なアクセス集中)への耐性を持たせるための構成。

### aws_appautoscaling_target

| 項目 | 値 |
|---|---|
| リソースID | `service/${project_name}-cluster/${project_name}-service` |
| スケーリング対象次元 | `ecs:service:DesiredCount` |
| サービスネームスペース | `ecs` |
| 最小キャパシティ | `${autoscaling_min_capacity}`（デフォルト: 1） |
| 最大キャパシティ | `${autoscaling_max_capacity}`（デフォルト: 4） |

### aws_appautoscaling_policy

| 項目 | 値 |
|---|---|
| ポリシー名 | `${project_name}-cpu-scaling` |
| ポリシータイプ | TargetTrackingScaling |
| 対象メトリクス | `ECSServiceAverageCPUUtilization`（事前定義メトリクス） |
| 目標値 | `${autoscaling_cpu_target_value}`（デフォルト: 70） |
| スケールアウトのクールダウン | 60秒 |
| スケールインのクールダウン | 300秒（急なスケールインを避けるため長めに設定） |

> **IAMロールについて**: ECSサービスのApplication Auto Scalingは、AWSが自動作成するサービスリンクロール（`AWSServiceRoleForApplicationAutoScaling_ECSService`）を使用するため、本リポジトリでIAMロールを追加定義する必要はない。

---

## CodeDeploy

### aws_codedeploy_app

| 項目 | 値 |
|---|---|
| アプリケーション名 | `${project_name}-deploy` |
| コンピュートプラットフォーム | ECS |

### aws_codedeploy_deployment_group

| 項目 | 値 |
|---|---|
| デプロイグループ名 | `${project_name}-deploy-group` |
| デプロイタイプ | BLUE_GREEN |
| デプロイ設定 | CodeDeployDefault.ECSAllAtOnce |
| 自動ロールバック | 有効（デプロイ失敗時に Blue（旧環境）へ自動で切り戻す） |
| ECSクラスター | `${project_name}-cluster` |
| ECSサービス | `${project_name}-service` |
| 本番リスナー | ALB :80 リスナー |
| テストリスナー | ALB :8080 リスナー |
| Blue ターゲットグループ | `${project_name}-tg-blue` |
| Green ターゲットグループ | `${project_name}-tg-green` |
| デプロイ後の元環境終了 | 5分後に自動終了 |
