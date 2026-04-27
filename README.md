# 🏦 Orquestrador de Onboarding Bancário em Go

> Sistema de orquestração de workflows baseado no padrão **Saga**, voltado para o processo de onboarding bancário. Desenvolvido com **Clean Architecture**, **Ports & Adapters** e concorrência nativa do Go. Infraestrutura local com **DynamoDB Local + SQS via LocalStack**.

---

## 📌 Visão Geral

Este projeto simula um cenário real de backend distribuído — semelhante ao que é utilizado em bancos, fintechs e plataformas cloud como AWS Step Functions. O sistema executa etapas de onboarding de forma ordenada, controla o estado da execução, aplica retry automático em falhas, executa rollback via compensação (padrão Saga) e garante **idempotência por CPF**.

---

## 🎯 Objetivos do Projeto

- Demonstrar uso avançado de Go em sistemas distribuídos
- Aplicar Clean Architecture com separação clara de responsabilidades
- Modelar domínio rico com regras de negócio isoladas
- Implementar concorrência real com goroutines, channels e context
- Simular infraestrutura AWS real (DynamoDB + SQS) 100% localmente via Docker
- Garantir idempotência — o mesmo CPF nunca gera dois onboardings simultâneos

---

## 🧠 Conceitos Aplicados

| Conceito | Descrição |
|---|---|
| Saga Pattern | Orquestração de transações distribuídas com compensação |
| Clean Architecture | Separação em camadas: Domain → Application → Interface → Infra |
| Ports & Adapters | Interfaces no domínio, implementações na infra |
| Goroutines + Channels | Worker pool para processamento assíncrono |
| Context | Cancelamento e timeout por execução |
| Retry com Backoff | Reexecução automática com espera incremental |
| Idempotência | Proteção contra execuções duplicadas por CPF |
| DynamoDB Local | Persistência real com AWS SDK, sem conta AWS |
| SQS (LocalStack) | Fila de mensagens gerenciada, substituindo channel puro |

---

## 🏗️ Stack Local

| Serviço | Tecnologia | Porta local |
|---|---|---|
| API | Go + Gin | `8080` |
| Banco de dados | DynamoDB Local (Docker) | `8000` |
| Fila de mensagens | SQS via LocalStack (Docker) | `4566` |

> Toda a infraestrutura sobe com um único `docker-compose up`. Nenhuma conta AWS é necessária.

---

## 🗂️ Estrutura de Pastas

```
onboarding-orchestrator/
├── cmd/
│   └── api/
│       └── main.go
│
├── internal/
│   ├── domain/
│   │   ├── onboarding.go
│   │   ├── step.go
│   │   ├── status.go
│   │   └── repository.go
│   │
│   ├── application/
│   │   ├── orchestrator.go
│   │   ├── onboarding_service.go
│   │   └── steps/
│   │       ├── validate_input.go
│   │       ├── check_fraud.go
│   │       ├── check_credit.go
│   │       ├── create_customer.go
│   │       ├── create_account.go
│   │       ├── enable_features.go
│   │       └── send_welcome.go
│   │
│   ├── interfaces/
│   │   └── http/
│   │       ├── handler.go
│   │       └── routes.go
│   │
│   └── infra/
│       ├── dynamo_repository.go       # Adapter: DynamoDB Local
│       ├── sqs_queue.go               # Adapter: SQS via LocalStack
│       └── worker.go
│
├── scripts/
│   └── setup_aws_local.sh             # Cria tabela DynamoDB e fila SQS
│
├── docker-compose.yml
├── go.mod
├── go.sum
└── README.md
```

### Por que essa estrutura?

- `domain/` não importa nada externo — é o núcleo puro do sistema
- `application/` depende só do domínio, nunca de Gin, DynamoDB ou SQS
- `interfaces/` traduz HTTP → domínio e domínio → HTTP
- `infra/` implementa as interfaces definidas no domínio (inversão de dependência)

---

## 🏗️ Arquitetura em Camadas

```
[ HTTP Request ]
      ↓
[ Handler (interfaces/http) ]        ← recebe e valida input
      ↓
[ OnboardingService (application) ]  ← caso de uso + idempotência
      ↓
[ Orchestrator (application) ]       ← executa workflow Saga
      ↓
[ Steps (domain) ]                   ← lógica de negócio de cada etapa
      ↓
[ DynamoRepository + SQSQueue (infra) ] ← DynamoDB Local + LocalStack
```

A dependência flui sempre **de fora para dentro**. O `domain` nunca sabe que existe Gin, DynamoDB ou SQS.

---

## 🐳 Infraestrutura Local com Docker

### `docker-compose.yml`

```yaml
version: "3.8"

services:
  dynamodb-local:
    image: amazon/dynamodb-local:latest
    container_name: dynamodb-local
    ports:
      - "8000:8000"
    command: "-jar DynamoDBLocal.jar -sharedDb -inMemory"

  localstack:
    image: localstack/localstack:latest
    container_name: localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=sqs
      - DEFAULT_REGION=us-east-1
      - AWS_DEFAULT_REGION=us-east-1
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
```

### Subir a infraestrutura

```bash
docker-compose up -d
```

---

## ⚙️ Script de Setup AWS Local

Após subir os containers, execute o script para criar a tabela no DynamoDB e a fila no SQS:

### `scripts/setup_aws_local.sh`

```bash
#!/bin/bash

DYNAMO_ENDPOINT="http://localhost:8000"
SQS_ENDPOINT="http://localhost:4566"
REGION="sa-east-1"
AWS_ARGS="--region $REGION --no-cli-pager \
          --aws-access-key-id local \
          --aws-secret-access-key local"

echo "🔧 Criando tabela DynamoDB..."
aws dynamodb create-table \
  --endpoint-url $DYNAMO_ENDPOINT \
  $AWS_ARGS \
  --table-name onboarding-executions \
  --attribute-definitions \
    AttributeName=ID,AttributeType=S \
    AttributeName=CPF,AttributeType=S \
  --key-schema \
    AttributeName=ID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes '[
    {
      "IndexName": "CPF-index",
      "KeySchema": [{"AttributeName":"CPF","KeyType":"HASH"}],
      "Projection": {"ProjectionType":"ALL"}
    }
  ]'

echo "✅ Tabela criada!"

echo "🔧 Criando fila SQS..."
aws sqs create-queue \
  --endpoint-url $SQS_ENDPOINT \
  $AWS_ARGS \
  --queue-name onboarding-queue

echo "✅ Fila criada!"
echo "🚀 Infraestrutura pronta."
```

```bash
chmod +x scripts/setup_aws_local.sh
./scripts/setup_aws_local.sh
```

> **Requisito:** AWS CLI instalado localmente. Para instalar: https://aws.amazon.com/cli/

---

## 🚀 Passo a Passo: Setup do Projeto

### 1. Inicializar o módulo Go

```bash
mkdir onboarding-orchestrator && cd onboarding-orchestrator
go mod init github.com/seu-usuario/onboarding-orchestrator
```

### 2. Instalar dependências

```bash
go get github.com/gin-gonic/gin
go get github.com/google/uuid
go get github.com/aws/aws-sdk-go-v2
go get github.com/aws/aws-sdk-go-v2/config
go get github.com/aws/aws-sdk-go-v2/credentials
go get github.com/aws/aws-sdk-go-v2/service/dynamodb
go get github.com/aws/aws-sdk-go-v2/service/dynamodb/types
go get github.com/aws/aws-sdk-go-v2/service/sqs
go get github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue
```

### 3. Subir infraestrutura e configurar

```bash
docker-compose up -d
./scripts/setup_aws_local.sh
```

### 4. Rodar a API

```bash
go run cmd/api/main.go
```

---

## 🧩 Implementação: Camada Domain

### `internal/domain/status.go`

```go
package domain

type Status string

const (
    Pending    Status = "PENDING"
    Running    Status = "RUNNING"
    Completed  Status = "COMPLETED"
    Failed     Status = "FAILED"
    RolledBack Status = "ROLLED_BACK"
)
```

### `internal/domain/step.go`

```go
package domain

import "context"

// Step é a interface que toda etapa do onboarding deve implementar.
type Step interface {
    Name() string
    Execute(ctx context.Context, data map[string]any) error
    Compensate(ctx context.Context, data map[string]any) error
}
```

### `internal/domain/onboarding.go`

```go
package domain

import "time"

type OnboardingExecution struct {
    ID        string
    CPF       string
    Nome      string
    Renda     float64
    Status    Status
    Step      int
    Data      map[string]any
    Error     string
    CreatedAt time.Time
    UpdatedAt time.Time
}
```

### `internal/domain/repository.go`

```go
package domain

// Repository é o Port de persistência.
// A implementação concreta fica na camada infra.
type Repository interface {
    Save(exec *OnboardingExecution) error
    Get(id string) (*OnboardingExecution, error)
    GetByCPF(cpf string) (*OnboardingExecution, error) // usado para idempotência
    List() ([]*OnboardingExecution, error)
}
```

---

## 🔁 Idempotência por CPF

A idempotência garante que um CPF não inicie dois processos de onboarding simultâneos ou duplicados. A verificação acontece na camada **Application**, antes de qualquer persistência.

### Regras de negócio

| Status da execução existente | Comportamento |
|---|---|
| `PENDING` ou `RUNNING` | 409 Conflict — onboarding em andamento |
| `COMPLETED` | 409 Conflict — onboarding já concluído |
| `FAILED` ou `ROLLED_BACK` | Permite nova tentativa |
| Não encontrado | Cria normalmente |

A consulta por CPF usa um **GSI (Global Secondary Index)** no DynamoDB, criado no script de setup.

---

## ⚙️ Implementação: Camada Application

### `internal/application/onboarding_service.go`

```go
package application

import (
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/seu-usuario/onboarding-orchestrator/internal/domain"
)

var (
    ErrOnboardingInProgress  = errors.New("já existe um onboarding em andamento para este CPF")
    ErrOnboardingAlreadyDone = errors.New("onboarding já foi concluído para este CPF")
)

type CreateOnboardingInput struct {
    CPF   string
    Nome  string
    Renda float64
}

// Queue é o Port da fila de mensagens.
type Queue interface {
    Send(exec *domain.OnboardingExecution) error
}

type OnboardingService struct {
    repo  domain.Repository
    queue Queue
}

func NewOnboardingService(repo domain.Repository, queue Queue) *OnboardingService {
    return &OnboardingService{repo: repo, queue: queue}
}

// Create verifica idempotência antes de criar uma nova execução.
func (s *OnboardingService) Create(input CreateOnboardingInput) (*domain.OnboardingExecution, error) {
    // --- Verificação de idempotência ---
    existing, err := s.repo.GetByCPF(input.CPF)
    if err == nil && existing != nil {
        switch existing.Status {
        case domain.Pending, domain.Running:
            return nil, ErrOnboardingInProgress
        case domain.Completed:
            return nil, ErrOnboardingAlreadyDone
        // FAILED e ROLLED_BACK: permite nova tentativa
        }
    }

    exec := &domain.OnboardingExecution{
        ID:        uuid.New().String(),
        CPF:       input.CPF,
        Nome:      input.Nome,
        Renda:     input.Renda,
        Status:    domain.Pending,
        Step:      0,
        Data:      map[string]any{"cpf": input.CPF, "nome": input.Nome, "renda": input.Renda},
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }

    if err := s.repo.Save(exec); err != nil {
        return nil, fmt.Errorf("erro ao salvar execução: %w", err)
    }

    if err := s.queue.Send(exec); err != nil {
        return nil, fmt.Errorf("erro ao enfileirar execução: %w", err)
    }

    return exec, nil
}

func (s *OnboardingService) GetStatus(id string) (*domain.OnboardingExecution, error) {
    return s.repo.Get(id)
}
```

### `internal/application/orchestrator.go`

```go
package application

import (
    "context"
    "fmt"
    "time"

    "github.com/seu-usuario/onboarding-orchestrator/internal/domain"
)

type Orchestrator struct {
    steps []domain.Step
    repo  domain.Repository
}

func NewOrchestrator(steps []domain.Step, repo domain.Repository) *Orchestrator {
    return &Orchestrator{steps: steps, repo: repo}
}

func (o *Orchestrator) Run(ctx context.Context, exec *domain.OnboardingExecution) {
    exec.Status = domain.Running
    o.repo.Save(exec)

    for i := exec.Step; i < len(o.steps); i++ {
        step := o.steps[i]

        err := o.executeWithRetry(ctx, step, exec, 3)
        if err != nil {
            exec.Error = fmt.Sprintf("step '%s' falhou: %v", step.Name(), err)
            o.rollback(ctx, exec, i)
            exec.Status = domain.Failed
            exec.UpdatedAt = time.Now()
            o.repo.Save(exec)
            return
        }

        exec.Step = i + 1
        exec.UpdatedAt = time.Now()
        o.repo.Save(exec)
    }

    exec.Status = domain.Completed
    exec.UpdatedAt = time.Now()
    o.repo.Save(exec)
}

func (o *Orchestrator) executeWithRetry(
    ctx context.Context,
    step domain.Step,
    exec *domain.OnboardingExecution,
    maxAttempts int,
) error {
    var lastErr error
    for attempt := 0; attempt < maxAttempts; attempt++ {
        if attempt > 0 {
            wait := time.Duration(attempt) * time.Second
            select {
            case <-ctx.Done():
                return ctx.Err()
            case <-time.After(wait):
            }
        }
        if err := step.Execute(ctx, exec.Data); err == nil {
            return nil
        } else {
            lastErr = err
        }
    }
    return fmt.Errorf("após %d tentativas: %w", maxAttempts, lastErr)
}

func (o *Orchestrator) rollback(ctx context.Context, exec *domain.OnboardingExecution, failedIndex int) {
    for i := failedIndex - 1; i >= 0; i-- {
        step := o.steps[i]
        if err := step.Compensate(ctx, exec.Data); err != nil {
            fmt.Printf("[ROLLBACK ERROR] step '%s': %v\n", step.Name(), err)
        }
    }
    exec.Status = domain.RolledBack
}
```

---

## 🧩 Steps do Onboarding

Crie um arquivo por step em `internal/application/steps/`:

| Step | Execute | Compensate |
|---|---|---|
| `ValidateInputStep` | Valida CPF e renda | — |
| `CheckFraudStep` | Consulta score antifraude | — |
| `CheckCreditStep` | Verifica limite de crédito | — |
| `CreateCustomerStep` | Cria cliente no sistema | Remove cliente |
| `CreateAccountStep` | Abre conta corrente | Fecha/remove conta |
| `EnableFeaturesStep` | Ativa produtos (cartão, Pix) | Desativa features |
| `SendWelcomeStep` | Envia e-mail de boas-vindas | — |

### Exemplo: `steps/create_account.go`

```go
package steps

import (
    "context"
    "fmt"
    "math/rand"
)

type CreateAccountStep struct{}

func (s CreateAccountStep) Name() string { return "CreateAccount" }

func (s CreateAccountStep) Execute(ctx context.Context, data map[string]any) error {
    // Simula chance de falha para demonstrar retry/rollback
    if rand.Float32() < 0.3 {
        return fmt.Errorf("serviço de contas indisponível (simulado)")
    }
    accountID := fmt.Sprintf("acc_%d", rand.Intn(99999))
    data["accountId"] = accountID
    fmt.Printf("[CreateAccount] Conta criada: %s\n", accountID)
    return nil
}

func (s CreateAccountStep) Compensate(ctx context.Context, data map[string]any) error {
    accountID, _ := data["accountId"].(string)
    fmt.Printf("[CreateAccount] ROLLBACK: removendo conta %s\n", accountID)
    delete(data, "accountId")
    return nil
}
```

---

## 🧰 Implementação: Camada Infra

### `internal/infra/dynamo_repository.go`

```go
package infra

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
    "github.com/seu-usuario/onboarding-orchestrator/internal/domain"
)

const tableName = "onboarding-executions"

type dynamoItem struct {
    ID        string  `dynamodbav:"ID"`
    CPF       string  `dynamodbav:"CPF"`
    Nome      string  `dynamodbav:"Nome"`
    Renda     float64 `dynamodbav:"Renda"`
    Status    string  `dynamodbav:"Status"`
    Step      int     `dynamodbav:"Step"`
    DataJSON  string  `dynamodbav:"DataJSON"`
    Error     string  `dynamodbav:"Error"`
    CreatedAt string  `dynamodbav:"CreatedAt"`
    UpdatedAt string  `dynamodbav:"UpdatedAt"`
}

type DynamoRepository struct {
    client *dynamodb.Client
}

func NewDynamoRepository(client *dynamodb.Client) *DynamoRepository {
    return &DynamoRepository{client: client}
}

func toItem(exec *domain.OnboardingExecution) (dynamoItem, error) {
    dataBytes, err := json.Marshal(exec.Data)
    if err != nil {
        return dynamoItem{}, err
    }
    return dynamoItem{
        ID: exec.ID, CPF: exec.CPF, Nome: exec.Nome, Renda: exec.Renda,
        Status: string(exec.Status), Step: exec.Step,
        DataJSON: string(dataBytes), Error: exec.Error,
        CreatedAt: exec.CreatedAt.Format(time.RFC3339),
        UpdatedAt: exec.UpdatedAt.Format(time.RFC3339),
    }, nil
}

func fromItem(item dynamoItem) (*domain.OnboardingExecution, error) {
    var data map[string]any
    if err := json.Unmarshal([]byte(item.DataJSON), &data); err != nil {
        return nil, err
    }
    createdAt, _ := time.Parse(time.RFC3339, item.CreatedAt)
    updatedAt, _ := time.Parse(time.RFC3339, item.UpdatedAt)
    return &domain.OnboardingExecution{
        ID: item.ID, CPF: item.CPF, Nome: item.Nome, Renda: item.Renda,
        Status: domain.Status(item.Status), Step: item.Step,
        Data: data, Error: item.Error,
        CreatedAt: createdAt, UpdatedAt: updatedAt,
    }, nil
}

func (r *DynamoRepository) Save(exec *domain.OnboardingExecution) error {
    item, err := toItem(exec)
    if err != nil {
        return fmt.Errorf("erro ao serializar execução: %w", err)
    }
    av, err := attributevalue.MarshalMap(item)
    if err != nil {
        return fmt.Errorf("erro ao converter para DynamoDB: %w", err)
    }
    _, err = r.client.PutItem(context.Background(), &dynamodb.PutItemInput{
        TableName: aws.String(tableName),
        Item:      av,
    })
    return err
}

func (r *DynamoRepository) Get(id string) (*domain.OnboardingExecution, error) {
    out, err := r.client.GetItem(context.Background(), &dynamodb.GetItemInput{
        TableName: aws.String(tableName),
        Key:       map[string]types.AttributeValue{"ID": &types.AttributeValueMemberS{Value: id}},
    })
    if err != nil {
        return nil, err
    }
    if out.Item == nil {
        return nil, fmt.Errorf("execução '%s' não encontrada", id)
    }
    var item dynamoItem
    if err := attributevalue.UnmarshalMap(out.Item, &item); err != nil {
        return nil, err
    }
    return fromItem(item)
}

// GetByCPF consulta o GSI "CPF-index" — usado para verificação de idempotência.
func (r *DynamoRepository) GetByCPF(cpf string) (*domain.OnboardingExecution, error) {
    out, err := r.client.Query(context.Background(), &dynamodb.QueryInput{
        TableName:              aws.String(tableName),
        IndexName:              aws.String("CPF-index"),
        KeyConditionExpression: aws.String("CPF = :cpf"),
        ExpressionAttributeValues: map[string]types.AttributeValue{
            ":cpf": &types.AttributeValueMemberS{Value: cpf},
        },
        Limit:            aws.Int32(1),
        ScanIndexForward: aws.Bool(false),
    })
    if err != nil {
        return nil, err
    }
    if len(out.Items) == 0 {
        return nil, nil
    }
    var item dynamoItem
    if err := attributevalue.UnmarshalMap(out.Items[0], &item); err != nil {
        return nil, err
    }
    return fromItem(item)
}

func (r *DynamoRepository) List() ([]*domain.OnboardingExecution, error) {
    out, err := r.client.Scan(context.Background(), &dynamodb.ScanInput{TableName: aws.String(tableName)})
    if err != nil {
        return nil, err
    }
    result := make([]*domain.OnboardingExecution, 0, len(out.Items))
    for _, av := range out.Items {
        var item dynamoItem
        if err := attributevalue.UnmarshalMap(av, &item); err != nil {
            continue
        }
        if exec, err := fromItem(item); err == nil {
            result = append(result, exec)
        }
    }
    return result, nil
}
```

### `internal/infra/sqs_queue.go`

```go
package infra

import (
    "context"
    "encoding/json"
    "fmt"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/sqs"
    "github.com/seu-usuario/onboarding-orchestrator/internal/domain"
)

type SQSQueue struct {
    client   *sqs.Client
    queueURL string
}

func NewSQSQueue(client *sqs.Client, queueURL string) *SQSQueue {
    return &SQSQueue{client: client, queueURL: queueURL}
}

func (q *SQSQueue) Send(exec *domain.OnboardingExecution) error {
    body, err := json.Marshal(exec)
    if err != nil {
        return fmt.Errorf("erro ao serializar mensagem: %w", err)
    }
    _, err = q.client.SendMessage(context.Background(), &sqs.SendMessageInput{
        QueueUrl:    aws.String(q.queueURL),
        MessageBody: aws.String(string(body)),
    })
    return err
}

// Receive faz long polling e retorna execuções + receipt handles para deleção posterior.
func (q *SQSQueue) Receive() ([]*domain.OnboardingExecution, []string, error) {
    out, err := q.client.ReceiveMessage(context.Background(), &sqs.ReceiveMessageInput{
        QueueUrl:            aws.String(q.queueURL),
        MaxNumberOfMessages: 10,
        WaitTimeSeconds:     5,
    })
    if err != nil {
        return nil, nil, err
    }
    var execs []*domain.OnboardingExecution
    var handles []string
    for _, msg := range out.Messages {
        var exec domain.OnboardingExecution
        if err := json.Unmarshal([]byte(*msg.Body), &exec); err != nil {
            continue
        }
        execs = append(execs, &exec)
        handles = append(handles, *msg.ReceiptHandle)
    }
    return execs, handles, nil
}

// Delete remove a mensagem da fila após processamento bem-sucedido.
func (q *SQSQueue) Delete(receiptHandle string) error {
    _, err := q.client.DeleteMessage(context.Background(), &sqs.DeleteMessageInput{
        QueueUrl:      aws.String(q.queueURL),
        ReceiptHandle: aws.String(receiptHandle),
    })
    return err
}
```

### `internal/infra/worker.go`

```go
package infra

import (
    "context"
    "fmt"

    "github.com/seu-usuario/onboarding-orchestrator/internal/application"
)

// StartWorkers inicia N goroutines que consomem mensagens do SQS
// e executam o orquestrador para cada execução recebida.
func StartWorkers(n int, queue *SQSQueue, orch *application.Orchestrator) {
    for i := 0; i < n; i++ {
        workerID := i + 1
        go func() {
            fmt.Printf("[Worker %d] iniciado\n", workerID)
            for {
                execs, handles, err := queue.Receive()
                if err != nil {
                    fmt.Printf("[Worker %d] erro ao receber da fila: %v\n", workerID, err)
                    continue
                }
                for j, exec := range execs {
                    fmt.Printf("[Worker %d] processando %s (CPF: %s)\n", workerID, exec.ID, exec.CPF)
                    orch.Run(context.Background(), exec)
                    fmt.Printf("[Worker %d] concluído: %s → %s\n", workerID, exec.ID, exec.Status)
                    queue.Delete(handles[j])
                }
            }
        }()
    }
}
```

---

## 🌐 Implementação: Camada HTTP

### `internal/interfaces/http/handler.go`

```go
package http

import (
    "errors"
    "net/http"

    "github.com/gin-gonic/gin"
    "github.com/seu-usuario/onboarding-orchestrator/internal/application"
)

type Handler struct {
    service *application.OnboardingService
}

func NewHandler(service *application.OnboardingService) *Handler {
    return &Handler{service: service}
}

type createRequest struct {
    CPF   string  `json:"cpf" binding:"required,len=11"`
    Nome  string  `json:"nome" binding:"required"`
    Renda float64 `json:"renda" binding:"required,gt=0"`
}

func (h *Handler) CreateOnboarding(c *gin.Context) {
    var req createRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    exec, err := h.service.Create(application.CreateOnboardingInput{
        CPF: req.CPF, Nome: req.Nome, Renda: req.Renda,
    })
    if err != nil {
        // Erros de idempotência retornam 409 Conflict
        if errors.Is(err, application.ErrOnboardingInProgress) ||
            errors.Is(err, application.ErrOnboardingAlreadyDone) {
            c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusAccepted, gin.H{
        "executionId": exec.ID,
        "status":      exec.Status,
        "message":     "onboarding iniciado com sucesso",
    })
}

func (h *Handler) GetOnboarding(c *gin.Context) {
    id := c.Param("id")
    exec, err := h.service.GetStatus(id)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, exec)
}
```

### `internal/interfaces/http/routes.go`

```go
package http

import "github.com/gin-gonic/gin"

func RegisterRoutes(r *gin.Engine, h *Handler) {
    api := r.Group("/api/v1")
    {
        api.POST("/onboarding", h.CreateOnboarding)
        api.GET("/onboarding/:id", h.GetOnboarding)
    }
}
```

---

## 🔌 Ponto de Entrada

### `cmd/api/main.go`

```go
package main

import (
    "context"
    "fmt"
    "log"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/credentials"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb"
    "github.com/aws/aws-sdk-go-v2/service/sqs"
    "github.com/gin-gonic/gin"

    "github.com/seu-usuario/onboarding-orchestrator/internal/application"
    "github.com/seu-usuario/onboarding-orchestrator/internal/application/steps"
    "github.com/seu-usuario/onboarding-orchestrator/internal/domain"
    "github.com/seu-usuario/onboarding-orchestrator/internal/infra"
    httpHandler "github.com/seu-usuario/onboarding-orchestrator/internal/interfaces/http"
)

func main() {
    ctx := context.Background()
    localCreds := credentials.NewStaticCredentialsProvider("local", "local", "")

    // DynamoDB Local
    dynCfg, err := config.LoadDefaultConfig(ctx,
        config.WithRegion("us-east-1"),
        config.WithCredentialsProvider(localCreds),
    )
    if err != nil {
        log.Fatalf("erro ao configurar DynamoDB: %v", err)
    }
    dynamoClient := dynamodb.NewFromConfig(dynCfg, func(o *dynamodb.Options) {
        o.BaseEndpoint = aws.String("http://localhost:8000")
    })

    // SQS via LocalStack
    sqsCfg, err := config.LoadDefaultConfig(ctx,
        config.WithRegion("us-east-1"),
        config.WithCredentialsProvider(localCreds),
    )
    if err != nil {
        log.Fatalf("erro ao configurar SQS: %v", err)
    }
    sqsClient := sqs.NewFromConfig(sqsCfg, func(o *sqs.Options) {
        o.BaseEndpoint = aws.String("http://localhost:4566")
    })

    sqsQueueURL := "http://localhost:4566/000000000000/onboarding-queue"

    // Infraestrutura
    repo := infra.NewDynamoRepository(dynamoClient)
    queue := infra.NewSQSQueue(sqsClient, sqsQueueURL)

    // Steps do workflow (ordem importa)
    workflowSteps := []domain.Step{
        steps.ValidateInputStep{},
        steps.CheckFraudStep{},
        steps.CheckCreditStep{},
        steps.CreateCustomerStep{},
        steps.CreateAccountStep{},
        steps.EnableFeaturesStep{},
        steps.SendWelcomeStep{},
    }

    // Application
    orchestrator := application.NewOrchestrator(workflowSteps, repo)
    service := application.NewOnboardingService(repo, queue)

    // Workers
    infra.StartWorkers(3, queue, orchestrator)
    fmt.Println("✅ 3 workers iniciados")

    // HTTP
    r := gin.Default()
    handler := httpHandler.NewHandler(service)
    httpHandler.RegisterRoutes(r, handler)

    fmt.Println("🚀 Servidor rodando em http://localhost:8080")
    r.Run(":8080")
}
```

---

## 🔄 Fluxo Completo com Idempotência

```
POST /api/v1/onboarding
        ↓
  Handler valida request (binding)
        ↓
  Service: GetByCPF → consulta GSI no DynamoDB
  ├── PENDING/RUNNING  → 409 Conflict
  ├── COMPLETED        → 409 Conflict
  └── FAILED/não existe → continua
        ↓
  Service salva execução (PENDING) no DynamoDB
        ↓
  Service envia mensagem para SQS (LocalStack)
        ↓
  Worker: long polling na fila SQS
        ↓
  Orchestrator.Run() → status: RUNNING
        ↓
  Step 1: ValidateInput  ✅
  Step 2: CheckFraud     ✅
  Step 3: CheckCredit    ✅
  Step 4: CreateCustomer ✅ → data["customerId"] = "cust_42"
  Step 5: CreateAccount  ❌ → falha após 3 tentativas (retry com backoff)
        ↓
  Rollback (ordem inversa):
    Step 4: CreateCustomer.Compensate() → remove cust_42
        ↓
  Status: FAILED → salvo no DynamoDB
  Worker deleta mensagem da fila SQS
```

---

## 🧪 Testando Localmente

### Criar onboarding

```bash
curl -X POST http://localhost:8080/api/v1/onboarding \
  -H "Content-Type: application/json" \
  -d '{"cpf": "12345678900", "nome": "Matheus", "renda": 5000}'
```

```json
{ "executionId": "abc-123", "status": "PENDING", "message": "onboarding iniciado com sucesso" }
```

### Testar idempotência (mesmo CPF em andamento)

```bash
curl -X POST http://localhost:8080/api/v1/onboarding \
  -H "Content-Type: application/json" \
  -d '{"cpf": "12345678900", "nome": "Matheus", "renda": 5000}'
```

```json
{ "error": "já existe um onboarding em andamento para este CPF" }
```
HTTP **409 Conflict**

### Consultar status

```bash
curl http://localhost:8080/api/v1/onboarding/abc-123
```

### Inspecionar DynamoDB local

```bash
aws dynamodb scan \
  --endpoint-url http://localhost:8000 \
  --table-name onboarding-executions \
  --region us-east-1 --no-cli-pager \
  --aws-access-key-id local --aws-secret-access-key local
```

### Inspecionar fila SQS

```bash
aws sqs get-queue-attributes \
  --endpoint-url http://localhost:4566 \
  --queue-url http://localhost:4566/000000000000/onboarding-queue \
  --attribute-names All \
  --region us-east-1 \
  --aws-access-key-id local --aws-secret-access-key local
```

---

## 🔥 Evoluções Futuras

| Evolução | Tecnologia sugerida |
|---|---|
| Timeout por step | `context.WithTimeout` em cada `Execute` |
| Retry com jitter | Aleatoriedade no backoff para evitar thundering herd |
| Observabilidade | `zap` (logs estruturados) + OpenTelemetry (tracing) |
| Steps paralelos | `errgroup` para execução concorrente |
| Deploy real na AWS | Substituir endpoints locais por variáveis de ambiente |
| Autenticação | JWT middleware no Gin |
| Testes unitários | `testify/mock` para Steps e Repository |
| Dead Letter Queue | SQS DLQ para mensagens com falha repetida |

---

## 📋 Checklist de Implementação (MVP Local)

- [ ] Configurar módulo Go e dependências
- [ ] Criar `docker-compose.yml` com DynamoDB Local e LocalStack
- [ ] Executar `setup_aws_local.sh` para criar tabela e fila
- [ ] Implementar `domain` (entidades, interfaces, status)
- [ ] Implementar `DynamoRepository` com GSI para busca por CPF
- [ ] Implementar `SQSQueue` (Send, Receive, Delete)
- [ ] Implementar os 7 steps com `Execute` e `Compensate`
- [ ] Implementar `Orchestrator` com retry e rollback
- [ ] Implementar `OnboardingService` com verificação de idempotência
- [ ] Implementar worker pool consumindo SQS
- [ ] Implementar handlers e rotas HTTP (Gin)
- [ ] Montar tudo em `main.go`
- [ ] Testar fluxo feliz via curl
- [ ] Testar idempotência com mesmo CPF em sequência
- [ ] Testar fluxo com falha simulada e verificar rollback no DynamoDB
- [ ] Inspecionar DynamoDB e SQS via AWS CLI
