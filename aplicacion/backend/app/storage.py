"""Almacenamiento de tareas: memoria (por defecto) o DynamoDB (si existe TASKS_TABLE)."""

from __future__ import annotations

import os
import threading
import uuid
from collections.abc import Mapping
from datetime import datetime, timezone
from typing import Any, Protocol

import boto3
from botocore.exceptions import ClientError


def _now() -> str:
    # Formato de ancho fijo para que el orden lexicografico coincida con el cronologico.
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _sort_key(task: dict[str, Any]) -> tuple[str, str]:
    return (task["created_at"], task["id"])


class TaskStore(Protocol):
    def list_tasks(self) -> list[dict[str, Any]]: ...

    def create_task(self, title: str) -> dict[str, Any]: ...

    def set_done(self, task_id: str, done: bool) -> dict[str, Any] | None: ...

    def delete_task(self, task_id: str) -> bool: ...


class MemoryTaskStore:
    """Almacenamiento en proceso. Los datos se pierden al reiniciar."""

    def __init__(self) -> None:
        self._items: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()

    def list_tasks(self) -> list[dict[str, Any]]:
        with self._lock:
            tasks = [dict(t) for t in self._items.values()]
        return sorted(tasks, key=_sort_key)

    def create_task(self, title: str) -> dict[str, Any]:
        task = {"id": uuid.uuid4().hex, "title": title, "done": False, "created_at": _now()}
        with self._lock:
            self._items[task["id"]] = task
        return dict(task)

    def set_done(self, task_id: str, done: bool) -> dict[str, Any] | None:
        with self._lock:
            task = self._items.get(task_id)
            if task is None:
                return None
            task["done"] = done
            return dict(task)

    def delete_task(self, task_id: str) -> bool:
        with self._lock:
            return self._items.pop(task_id, None) is not None


def _to_task(item: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(item["id"]),
        "title": str(item.get("title", "")),
        "done": bool(item.get("done", False)),
        "created_at": str(item.get("created_at", "")),
    }


class DynamoTaskStore:
    """Almacenamiento en DynamoDB. Usa solo GetItem, PutItem, UpdateItem, DeleteItem y Scan.

    Los recursos de boto3 no son seguros entre hilos, asi que cada hilo crea el suyo.
    """

    def __init__(self, table_name: str, region_name: str | None = None) -> None:
        self._table_name = table_name
        self._region_name = region_name
        self._local = threading.local()

    def _table(self) -> Any:
        table = getattr(self._local, "table", None)
        if table is None:
            resource = boto3.resource("dynamodb", region_name=self._region_name)
            table = resource.Table(self._table_name)
            self._local.table = table
        return table

    def list_tasks(self) -> list[dict[str, Any]]:
        table = self._table()
        items: list[dict[str, Any]] = []
        kwargs: dict[str, Any] = {}
        while True:
            page = table.scan(**kwargs)
            items.extend(page.get("Items", []))
            last_key = page.get("LastEvaluatedKey")
            if not last_key:
                break
            kwargs["ExclusiveStartKey"] = last_key
        tasks = [_to_task(i) for i in items]
        return sorted(tasks, key=_sort_key)

    def create_task(self, title: str) -> dict[str, Any]:
        task = {"id": uuid.uuid4().hex, "title": title, "done": False, "created_at": _now()}
        self._table().put_item(Item=task, ConditionExpression="attribute_not_exists(id)")
        return dict(task)

    def set_done(self, task_id: str, done: bool) -> dict[str, Any] | None:
        try:
            response = self._table().update_item(
                Key={"id": task_id},
                UpdateExpression="SET #done = :done",
                ExpressionAttributeNames={"#done": "done"},
                ExpressionAttributeValues={":done": done},
                ConditionExpression="attribute_exists(id)",
                ReturnValues="ALL_NEW",
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return None
            raise
        return _to_task(response["Attributes"])

    def delete_task(self, task_id: str) -> bool:
        try:
            self._table().delete_item(
                Key={"id": task_id},
                ConditionExpression="attribute_exists(id)",
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return False
            raise
        return True


def store_from_env(env: Mapping[str, str] | None = None) -> TaskStore:
    """Elige DynamoDB si TASKS_TABLE esta definida; si no, memoria."""
    source = os.environ if env is None else env
    table_name = (source.get("TASKS_TABLE") or "").strip()
    if table_name:
        region = (source.get("AWS_REGION") or "").strip() or None
        return DynamoTaskStore(table_name, region_name=region)
    return MemoryTaskStore()
