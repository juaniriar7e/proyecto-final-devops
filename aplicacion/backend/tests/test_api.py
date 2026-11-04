"""Contrato HTTP de la API. Cada test corre dos veces: almacenamiento en memoria y DynamoDB (moto)."""

import uuid

from tests.conftest import TEST_VERSION


def test_health_returns_ok(client):
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_uses_app_version(client):
    response = client.get("/api/version")
    assert response.status_code == 200
    assert response.json() == {"version": TEST_VERSION, "service": "backend"}


def test_list_starts_empty(client):
    response = client.get("/api/tasks")
    assert response.status_code == 200
    assert response.json() == []


def test_create_task_returns_201_and_defaults(client):
    response = client.post("/api/tasks", json={"title": "Comprar leche"})
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Comprar leche"
    assert body["done"] is False
    assert body["id"]
    assert body["created_at"]


def test_create_strips_surrounding_spaces(client):
    response = client.post("/api/tasks", json={"title": "   Estudiar   "})
    assert response.status_code == 201
    assert response.json()["title"] == "Estudiar"


def test_create_rejects_blank_title(client):
    for title in ["", "   ", "\t\n"]:
        response = client.post("/api/tasks", json={"title": title})
        assert response.status_code == 422, title


def test_create_rejects_missing_or_too_long_title(client):
    assert client.post("/api/tasks", json={}).status_code == 422
    assert client.post("/api/tasks", json={"title": "x" * 201}).status_code == 422


def test_full_crud_flow(client):
    created = client.post("/api/tasks", json={"title": "Tarea CRUD"}).json()
    task_id = created["id"]

    listed = client.get("/api/tasks").json()
    assert [t["id"] for t in listed] == [task_id]

    patched = client.patch(f"/api/tasks/{task_id}", json={"done": True})
    assert patched.status_code == 200
    assert patched.json()["done"] is True
    assert patched.json()["title"] == "Tarea CRUD"

    patched_back = client.patch(f"/api/tasks/{task_id}", json={"done": False})
    assert patched_back.json()["done"] is False

    deleted = client.delete(f"/api/tasks/{task_id}")
    assert deleted.status_code == 204
    assert deleted.content == b""

    assert client.get("/api/tasks").json() == []


def test_list_keeps_creation_order(client):
    titles = ["primera", "segunda", "tercera"]
    for title in titles:
        client.post("/api/tasks", json={"title": title})
    listed = client.get("/api/tasks").json()
    assert [t["title"] for t in listed] == titles


def test_patch_unknown_task_returns_404(client):
    response = client.patch(f"/api/tasks/{uuid.uuid4().hex}", json={"done": True})
    assert response.status_code == 404


def test_patch_requires_boolean_done(client):
    task_id = client.post("/api/tasks", json={"title": "Validar"}).json()["id"]
    assert client.patch(f"/api/tasks/{task_id}", json={}).status_code == 422
    assert client.patch(f"/api/tasks/{task_id}", json={"done": "no-es-bool"}).status_code == 422


def test_delete_unknown_task_returns_404(client):
    assert client.delete(f"/api/tasks/{uuid.uuid4().hex}").status_code == 404


def test_deleting_twice_returns_404_second_time(client):
    task_id = client.post("/api/tasks", json={"title": "Doble borrado"}).json()["id"]
    assert client.delete(f"/api/tasks/{task_id}").status_code == 204
    assert client.delete(f"/api/tasks/{task_id}").status_code == 404
