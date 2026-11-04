"""Seleccion de almacenamiento y persistencia de DynamoDB (simulado con moto)."""

import boto3
from fastapi.testclient import TestClient
from moto import mock_aws

from app.main import create_app
from app.storage import DynamoTaskStore, MemoryTaskStore, store_from_env
from tests.conftest import REGION, TABLE_NAME, create_tasks_table


def test_store_is_memory_without_tasks_table():
    assert isinstance(store_from_env({}), MemoryTaskStore)
    assert isinstance(store_from_env({"TASKS_TABLE": "   "}), MemoryTaskStore)


def test_store_is_dynamodb_when_tasks_table_is_set():
    store = store_from_env({"TASKS_TABLE": TABLE_NAME, "AWS_REGION": REGION})
    assert isinstance(store, DynamoTaskStore)


def test_app_reads_store_from_environment(aws_env_table):
    # Sin store explicito, create_app elige DynamoDB porque TASKS_TABLE esta definida.
    with mock_aws():
        create_tasks_table()
        app = create_app(app_version="env-test")
        with TestClient(app) as client:
            created = client.post("/api/tasks", json={"title": "Desde entorno"})
            assert created.status_code == 201
            assert [t["title"] for t in client.get("/api/tasks").json()] == ["Desde entorno"]


def test_tasks_persist_across_app_instances_in_dynamodb():
    with mock_aws():
        create_tasks_table()
        first = create_app(store=DynamoTaskStore(TABLE_NAME, region_name=REGION), app_version="a")
        with TestClient(first) as client:
            task_id = client.post("/api/tasks", json={"title": "Sobrevive"}).json()["id"]

        # Una instancia nueva (como tras un redeploy) debe ver la misma tarea.
        second = create_app(store=DynamoTaskStore(TABLE_NAME, region_name=REGION), app_version="b")
        with TestClient(second) as client:
            listed = client.get("/api/tasks").json()
            assert [t["id"] for t in listed] == [task_id]

        # Y los items reales deben estar en la tabla con el esquema esperado.
        table = boto3.resource("dynamodb", region_name=REGION).Table(TABLE_NAME)
        items = table.scan()["Items"]
        assert len(items) == 1
        assert items[0]["id"] == task_id
        assert items[0]["done"] is False
