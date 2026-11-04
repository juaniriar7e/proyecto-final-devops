import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import TaskList from './TaskList.jsx';

const tasks = [
  { id: 'a1', title: 'Pendiente', done: false, created_at: '2026-01-01T00:00:00.000000Z' },
  { id: 'b2', title: 'Hecha', done: true, created_at: '2026-01-02T00:00:00.000000Z' },
];

describe('TaskList', () => {
  it('muestra cada tarea con su estado de completado', () => {
    render(<TaskList tasks={tasks} onToggle={vi.fn()} onDelete={vi.fn()} />);
    expect(screen.getByText('Pendiente')).toBeTruthy();
    expect(screen.getByRole('checkbox', { name: 'Completar Pendiente' }).checked).toBe(false);
    expect(screen.getByRole('checkbox', { name: 'Completar Hecha' }).checked).toBe(true);
  });

  it('llama a onToggle con la tarea al cambiar el checkbox', () => {
    const onToggle = vi.fn();
    render(<TaskList tasks={tasks} onToggle={onToggle} onDelete={vi.fn()} />);
    fireEvent.click(screen.getByRole('checkbox', { name: 'Completar Pendiente' }));
    expect(onToggle).toHaveBeenCalledWith(tasks[0]);
  });

  it('llama a onDelete con la tarea al pulsar Borrar', () => {
    const onDelete = vi.fn();
    render(<TaskList tasks={tasks} onToggle={vi.fn()} onDelete={onDelete} />);
    fireEvent.click(screen.getByRole('button', { name: 'Borrar Hecha' }));
    expect(onDelete).toHaveBeenCalledWith(tasks[1]);
  });
});
