"""API de gestion de tareas. Todas las rutas cuelgan de /api (el ALB y el gateway mandan /api/* aqui)."""

import os

from fastapi import APIRouter, FastAPI, HTTPException, Response

from app.models import Task, TaskCreate, TaskUpdate
from app.storage import TaskStore, store_from_env


def create_app(store: TaskStore | None = None, app_version: str | None = None) -> FastAPI:
    version = app_version if app_version is not None else (os.environ.get("APP_VERSION") or "dev")
    tasks = store if store is not None else store_from_env()

    app = FastAPI(title="triplepipe backend", version=version)
    api = APIRouter(prefix="/api")

    @api.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/version")
    def get_version() -> dict[str, str]:
        return {"version": version, "service": "backend"}

    @api.get("/tasks", response_model=list[Task])
    def list_tasks() -> list[dict]:
        return tasks.list_tasks()

    @api.post("/tasks", response_model=Task, status_code=201)
    def create_task(body: TaskCreate) -> dict:
        return tasks.create_task(body.title)

    @api.patch("/tasks/{task_id}", response_model=Task)
    def update_task(task_id: str, body: TaskUpdate) -> dict:
        task = tasks.set_done(task_id, body.done)
        if task is None:
            raise HTTPException(status_code=404, detail="Tarea no encontrada")
        return task

    @api.delete("/tasks/{task_id}", status_code=204)
    def delete_task(task_id: str) -> Response:
        if not tasks.delete_task(task_id):
            raise HTTPException(status_code=404, detail="Tarea no encontrada")
        return Response(status_code=204)

    app.include_router(api)
    return app


app = create_app()
