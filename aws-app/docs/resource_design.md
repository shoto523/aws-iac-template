# リソース詳細設計書（aws-app）

Terraform 実装は作成中のため、本ファイルは設計意図に基づく仕様記載。実装完了後に実コードと照合して更新する。`${project_name}` はユーザーが `terraform.tfvars` で設定する値。

---

## IAM

### ECS Task Execution ロール

| 項目 | 値（予定） |
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

| 項目 | 値（予定） |
|---|---|
| ロール名 | `${project_name}-ecs-task-role` |
| 信頼するサービス | `ecs-tasks.amazonaws.com` |
| ポリシー | アプリ要件に応じて追加（初期は空） |

### CodeDeploy 実行ロール

| 項目 | 値（予定） |
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

| 項目 | 値（予定） |
|---|---|
| ALB名 | `${project_name}-alb` |
| タイプ | application |
| 配置サブネット | `${public_subnet_ids}`（入力パラメータ） |
| セキュリティグループ | `${alb_security_group_id}`（入力パラメータ） |
| 内部/外部 | internet-facing |

### aws_lb_target_group（Blue）

| 項目 | 値（予定） |
|---|---|
| ターゲットグループ名 | `${project_name}-tg-blue` |
| ターゲットタイプ | ip（Fargate使用のため） |
| プロトコル | HTTP |
| ポート | `${container_port}` |
| VPC | `${vpc_id}` |

### aws_lb_target_group（Green）

| 項目 | 値（予定） |
|---|---|
| ターゲットグループ名 | `${project_name}-tg-green` |
| ターゲットタイプ | ip |
| プロトコル | HTTP |
| ポート | `${container_port}` |
| VPC | `${vpc_id}` |

### aws_lb_listener（本番 :80）

| 項目 | 値（予定） |
|---|---|
| ポート | 80 |
| プロトコル | HTTP |
| デフォルトアクション | forward → Blue ターゲットグループ |

### aws_lb_listener（テスト :8080）

| 項目 | 値（予定） |
|---|---|
| ポート | 8080 |
| プロトコル | HTTP |
| デフォルトアクション | forward → Green ターゲットグループ |

---

## ECS

### aws_ecs_cluster

| 項目 | 値（予定） |
|---|---|
| クラスター名 | `${project_name}-cluster` |

### aws_ecs_task_definition

| 項目 | 値（予定） |
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

| 項目 | 値（予定） |
|---|---|
| サービス名 | `${project_name}-service` |
| クラスター | `${project_name}-cluster` |
| 起動タイプ | FARGATE |
| デプロイコントローラー | CODE_DEPLOY（Blue/Green用） |
| 希望タスク数 | 1 |
| サブネット | `${private_subnet_ids}` |
| セキュリティグループ | `${ecs_security_group_id}` |
| パブリックIP割り当て | 無効 |
| ロードバランサー | Blue ターゲットグループ |

---

## CodeDeploy

### aws_codedeploy_app

| 項目 | 値（予定） |
|---|---|
| アプリケーション名 | `${project_name}-deploy` |
| コンピュートプラットフォーム | ECS |

### aws_codedeploy_deployment_group

| 項目 | 値（予定） |
|---|---|
| デプロイグループ名 | `${project_name}-deploy-group` |
| デプロイタイプ | BLUE_GREEN |
| デプロイ設定 | CodeDeployDefault.ECSAllAtOnce |
| ECSクラスター | `${project_name}-cluster` |
| ECSサービス | `${project_name}-service` |
| 本番リスナー | ALB :80 リスナー |
| テストリスナー | ALB :8080 リスナー |
| Blue ターゲットグループ | `${project_name}-tg-blue` |
| Green ターゲットグループ | `${project_name}-tg-green` |
| デプロイ後の元環境終了 | 5分後に自動終了 |
