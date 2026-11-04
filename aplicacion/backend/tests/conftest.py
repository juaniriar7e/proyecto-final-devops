"""Fixtures compartidas. Ningun test usa AWS real: DynamoDB se simula con moto."""

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from app.main import create_app
from app.storage import DynamoTaskStore, MemoryTaskStore

TABLE_NAME = "triplepipe-test-tasks"
REGION = "us-east-1"
TEST_VERSION = "9.9.9-test"


@pytest.fixture(autouse=True)
def _fake_aws_environment(monkeypatch):
    # Credenciales falsas: si algo intentara llamar a AWS real, fallaria por autenticacion.
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    monkeypatch.delenv("TASKS_TABLE", raising=False)
    monkeypatch.delenv("APP_VERSION", raising=False)
    yield


def create_tasks_table() -> None:
    dynamodb = boto3.resource("dynamodb", region_name=REGION)
    dynamodb.create_table(
        TableName=TABLE_NAME,
        KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )


@pytest.fixture(params=["memory", "dynamodb"])
def backend_kind(request):
    return request.param


@pytest.fixture
def client(backend_kind):
    if backend_kind == "memory":
        app = create_app(store=MemoryTaskStore(), app_version=TEST_VERSION)
        with TestClient(app) as test_client:
            yield test_client
    else:
        with mock_aws():
            create_tasks_table()
            store = DynamoTaskStore(TABLE_NAME, region_name=REGION)
            app = create_app(store=store, app_version=TEST_VERSION)
            with TestClient(app) as test_client:
                yield test_client


@pytest.fixture
def aws_env_table(monkeypatch):
    """Entorno como en ECS: TASKS_TABLE y AWS_REGION definidos."""
    monkeypatch.setenv("TASKS_TABLE", TABLE_NAME)
    monkeypatch.setenv("AWS_REGION", REGION)
    yield
