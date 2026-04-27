#!/bin/bash

COMMAND=${1:-up}

case "$COMMAND" in
  up)
    docker compose up -d
    echo "Aguardando setup da infraestrutura..."
    docker logs -f aws-setup &
    LOGS_PID=$!
    docker wait aws-setup
    kill $LOGS_PID 2>/dev/null
    wait $LOGS_PID 2>/dev/null
    echo ""
    echo "Servicos disponiveis:"
    echo "  DynamoDB Local:  http://localhost:8000"
    echo "  DynamoDB Admin:  http://localhost:8001"
    echo "  LocalStack SQS:  http://localhost:4566"
    ;;
  down)
    docker compose down
    ;;
  restart)
    docker compose down
    docker compose up -d
    docker logs -f aws-setup &
    LOGS_PID=$!
    docker wait aws-setup
    kill $LOGS_PID 2>/dev/null
    wait $LOGS_PID 2>/dev/null
    ;;
  logs)
    docker compose logs -f
    ;;
  ps)
    docker compose ps
    ;;
  *)
    echo "Uso: ./dev.sh [up|down|restart|logs|ps]"
    exit 1
    ;;
esac
