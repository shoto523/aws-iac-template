# GitHub 接続セットアップ手順書

## 概要

GitHub リポジトリと AWS CodePipeline を接続するための設定手順です。  
接続方式は **AWS CodeStar Connections** を使用します。

> **前提**: IaC（GitHub版）のデプロイが完了していること。  
> CodeStar Connections はIaC（`02-source-github.yaml` / `source-github` モジュール）によって自動作成されますが、**GitHub との手動承認が別途必要**です。

---

## 前提条件

| 項目 | 確認方法 |
|---|---|
| AWS CLI v2 インストール済み | `aws --version` |
| AWS 認証情報設定済み | `aws sts get-caller-identity` |
| GitHub アカウントを所持していること | — |
| IaC（GitHub版）のデプロイ完了 | CodeStar Connections が「保留中」状態で存在すること |

---

## Step 1: CodeStar Connections の接続ARNを確認する（ローカル操作）

IaC デプロイ後に作成された接続を確認します。

```powershell
aws codestar-connections list-connections `
  --region ap-northeast-1 `
  --query "Connections[*].{Name:ConnectionName, Status:ConnectionStatus, ARN:ConnectionArn}" `
  --output table
```

出力例：

```
----------------------------------------------------------------------
|                         ListConnections                            |
+---------------------+------------------+---------------------------+
|         ARN         |      Name        |          Status           |
+---------------------+------------------+---------------------------+
|  arn:aws:...        |  my-app-github   |  PENDING                  |
+---------------------+------------------+---------------------------+
```

`PENDING` 状態の接続が表示されれば正常です。次のステップで承認します。

---

## Step 2: GitHub との接続を手動承認する（AWS コンソール操作）

CodeStar Connections は作成直後 `PENDING` 状態のため、AWS コンソールから GitHub アカウントとの接続を承認する必要があります。

1. AWS コンソール → **CodePipeline** → 左メニュー **設定** → **接続**
2. 対象の接続（`PENDING` 状態）を選択
3. **保留中の接続を更新** をクリック
4. **GitHub に接続** をクリック
5. GitHub の認可画面が開くので **Authorize AWS Connector for GitHub** をクリック
6. 接続ステータスが `AVAILABLE` に変わることを確認

---

## Step 3: 接続ステータスを確認する（ローカル操作）

```powershell
aws codestar-connections list-connections `
  --region ap-northeast-1 `
  --query "Connections[*].{Name:ConnectionName, Status:ConnectionStatus}" `
  --output table
```

`AVAILABLE` になっていれば接続完了です。

---

## Step 4: CodePipeline の動作確認（ローカル操作 + AWS コンソール確認）

GitHub リポジトリに push して CodePipeline が自動起動することを確認します。

```powershell
# アプリリポジトリで変更をpush（例）
git push origin main
```

push 後、AWS コンソールで確認します。

1. AWS コンソール → **CodePipeline** → パイプライン一覧
2. 対象パイプラインを選択
3. Source Stage が自動的に開始されることを確認

---

## トラブルシューティング

### 接続が `PENDING` のままで `AVAILABLE` にならない場合

- Step 2 の手動承認が完了しているか確認する
- AWS コンソール → **CodePipeline** → **設定** → **接続** から再度承認を試みる

### `AVAILABLE` なのに CodePipeline が起動しない場合

- IaC のパラメータ（`github_owner`・`github_repo`・`github_branch`）が正しいか確認する
- GitHub リポジトリが存在し、指定ブランチへの push 権限があるか確認する

### 接続の ARN が IaC パラメータと一致しているか確認する

```powershell
aws codestar-connections list-connections `
  --region ap-northeast-1 `
  --query "Connections[?ConnectionStatus=='AVAILABLE'].ConnectionArn" `
  --output text
```

表示された ARN が IaC の `connection_arn` パラメータと一致していることを確認する。
