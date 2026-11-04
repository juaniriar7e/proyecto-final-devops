function label(value) {
  if (value === undefined) {
    return 'cargando...';
  }
  return value ?? 'no disponible';
}

export default function VersionFooter({ frontendVersion, backendVersion }) {
  return (
    <footer className="version-footer">
      <span>Frontend: {label(frontendVersion)}</span>
      <span>Backend: {label(backendVersion)}</span>
    </footer>
  );
}
