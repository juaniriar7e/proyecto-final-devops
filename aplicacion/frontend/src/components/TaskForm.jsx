import { useState } from 'react';

export default function TaskForm({ onCreate }) {
  const [title, setTitle] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const trimmed = title.trim();
  const canSubmit = trimmed.length > 0 && !submitting;

  async function handleSubmit(event) {
    event.preventDefault();
    if (!canSubmit) {
      return;
    }
    setSubmitting(true);
    try {
      await onCreate(trimmed);
      setTitle('');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="task-form" onSubmit={handleSubmit}>
      <label className="visually-hidden" htmlFor="new-task">
        Nueva tarea
      </label>
      <input
        id="new-task"
        type="text"
        placeholder="¿Qué hay que hacer?"
        maxLength={200}
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        disabled={submitting}
      />
      <button type="submit" disabled={!canSubmit}>
        {submitting ? 'Agregando...' : 'Agregar'}
      </button>
    </form>
  );
}
