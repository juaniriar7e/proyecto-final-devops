"""Esquemas de entrada y salida de la API de tareas."""

from pydantic import BaseModel, Field, field_validator

TITLE_MAX_LENGTH = 200


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=TITLE_MAX_LENGTH)

    @field_validator("title")
    @classmethod
    def _strip_and_require_text(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("El titulo no puede estar vacio")
        return stripped


class TaskUpdate(BaseModel):
    done: bool


class Task(BaseModel):
    id: str
    title: str
    done: bool
    created_at: str
