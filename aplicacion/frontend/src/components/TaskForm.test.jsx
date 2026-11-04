import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import TaskForm from './TaskForm.jsx';

describe('TaskForm', () => {
  it('deshabilita el botón mientras el título está vacío o solo tiene espacios', () => {
    render(<TaskForm onCreate={vi.fn()} />);
    const button = screen.getByRole('button', { name: 'Agregar' });
    expect(button.disabled).toBe(true);

    fireEvent.change(screen.getByRole('textbox'), { target: { value: '   ' } });
    expect(button.disabled).toBe(true);
  });

  it('envía el título sin espacios sobrantes y limpia el campo', async () => {
    const onCreate = vi.fn().mockResolvedValue(undefined);
    render(<TaskForm onCreate={onCreate} />);
    const input = screen.getByRole('textbox');

    fireEvent.change(input, { target: { value: '  Comprar pan  ' } });
    fireEvent.click(screen.getByRole('button', { name: 'Agregar' }));

    expect(onCreate).toHaveBeenCalledTimes(1);
    expect(onCreate).toHaveBeenCalledWith('Comprar pan');
    await waitFor(() => expect(input.value).toBe(''));
  });

  it('no envía nada al enviar el formulario con el título vacío', () => {
    const onCreate = vi.fn();
    render(<TaskForm onCreate={onCreate} />);
    fireEvent.submit(screen.getByRole('textbox').closest('form'));
    expect(onCreate).not.toHaveBeenCalled();
  });
});
