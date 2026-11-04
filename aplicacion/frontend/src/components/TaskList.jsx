export default function TaskList({ tasks, onToggle, onDelete }) {
  return (
    <ul className="task-list">
      {tasks.map((task) => (
        <li key={task.id} className={task.done ? 'task done' : 'task'}>
          <label className="task-label">
            <input
              type="checkbox"
              checked={task.done}
              onChange={() => onToggle(task)}
              aria-label={`Completar ${task.title}`}
            />
            <span className="task-title">{task.title}</span>
          </label>
          <button
            type="button"
            className="delete"
            onClick={() => onDelete(task)}
            aria-label={`Borrar ${task.title}`}
          >
            Borrar
          </button>
        </li>
      ))}
    </ul>
  );
}
