// Cliente HTTP. Todas las rutas son relativas: el mismo origen sirve frontend y /api.

async function request(path, options = {}) {
  let response;
  try {
    response = await fetch(path, options);
  } catch {
    throw new Error('No se pudo conectar con el servidor. Revisa tu conexión.');
  }

  if (!response.ok) {
    let detail = `Error ${response.status} al comunicarse con el servidor`;
    try {
      const body = await response.json();
      if (typeof body.detail === 'string') {
        detail = body.detail;
      } else if (Array.isArray(body.detail)) {
        detail = 'Los datos enviados no son válidos';
      }
    } catch {
      // Respuesta sin JSON: se conserva el mensaje generico.
    }
    throw new Error(detail);
  }

  if (response.status === 204) {
    return null;
  }
  return response.json();
}

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function listTasks() {
  return request('/api/tasks');
}

export function createTask(title) {
  return request('/api/tasks', {
    method: 'POST',
    headers: JSON_HEADERS,
    body: JSON.stringify({ title }),
  });
}

export function setTaskDone(id, done) {
  return request(`/api/tasks/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: JSON_HEADERS,
    body: JSON.stringify({ done }),
  });
}

export function deleteTask(id) {
  return request(`/api/tasks/${encodeURIComponent(id)}`, { method: 'DELETE' });
}

export function getBackendVersion() {
  return request('/api/version').then((body) => body.version);
}

export async function getFrontendVersion() {
  const response = await fetch('/version.json', { cache: 'no-store' });
  if (!response.ok) {
    throw new Error('version.json no disponible');
  }
  const body = await response.json();
  return body.version;
}
