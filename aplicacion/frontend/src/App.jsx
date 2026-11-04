import { useCallback, useEffect, useState } from 'react';
import {
  createTask,
  deleteTask,
  getBackendVersion,
  getFrontendVersion,
  listTasks,
  setTaskDone,
} from './api.js';
import TaskForm from './components/TaskForm.jsx';
import TaskList from './components/TaskList.jsx';
import VersionFooter from './components/VersionFooter.jsx';

export default function App() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [frontendVersion, setFrontendVersion] = useState(undefined);
  const [backendVersion, setBackendVersion] = useState(undefined);

  const loadTasks = useCallback(async () => {
    setLoading(true);
    try {
      setTasks(await listTasks());
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTasks();
    getFrontendVersion()
      .then(setFrontendVersion)
      .catch(() => setFrontendVersion(null));
    getBackendVersion()
      .then(setBackendVersion)
      .catch(() => setBackendVersion(null));
  }, [loadTasks]);

  // Las acciones no lanzan excepciones: el error se muestra en la barra superior.
  async function handleCreate(title) {
    try {
      const task = await createTask(title);
      setTasks((prev) => [...prev, task]);
      setError(null);
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleToggle(task) {
    try {
      const updated = await setTaskDone(task.id, !task.done);
      setTasks((prev) => prev.map((t) => (t.id === updated.id ? updated : t)));
      setError(null);
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleDelete(task) {
    try {
      await deleteTask(task.id);
      setTasks((prev) => prev.filter((t) => t.id !== task.id));
      setError(null);
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <main className="app">
      <header>
        <h1>Gestor de tareas</h1>
      </header>

      <TaskForm onCreate={handleCreate} />

      {error && (
        <div className="banner error" role="alert">
          <span>{error}</span>
          <button type="button" onClick={() => setError(null)}>
            Cerrar
          </button>
        </div>
      )}

      {loading && (
        <p className="status" role="status">
          Cargando tareas...
        </p>
      )}

      {!loading && tasks.length > 0 && (
        <TaskList tasks={tasks} onToggle={handleToggle} onDelete={handleDelete} />
      )}

      {!loading && tasks.length === 0 && !error && (
        <p className="status">No hay tareas pendientes. Agrega la primera arriba.</p>
      )}

      {!loading && error && tasks.length === 0 && (
        <button type="button" className="retry" onClick={loadTasks}>
          Reintentar
        </button>
      )}

      <VersionFooter frontendVersion={frontendVersion} backendVersion={backendVersion} />
    </main>
  );
}
