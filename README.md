# Gestor de Asistencias — Flutter para Windows (versión 2 inicial)

## Ejecutar
```powershell
flutter clean
flutter pub get
flutter run -d windows
```
Si aún no se creó la plataforma Windows:
```powershell
flutter create . --platforms=windows
```

## Pantalla inicial y cuentas
- Dos accesos separados: administrador y personal de asistencia.
- Tercer botón pequeño: Crear cuenta de administrador.
- En el primer uso, el primer administrador se registra desde ese tercer botón.
- Luego, crear otra cuenta requiere iniciar sesión como administrador.
- El administrador puede crear cuentas de personal desde la opción de su panel.
- Cada cuenta recibe un código de recuperación de cuatro dígitos que se muestra una sola vez.

## Panel y clasificación
- Panel con accesos para alumnos, personal, escáner QR, registro manual, reportes y horarios.
- Personal ve un panel reducido.
- Estados definidos: TEMPRANO, TARDE y FALTA. No existe estado PUNTUAL.
- SQLite local; tablas iniciales para usuarios, alumnos, asistencias y horarios.

## Alcance de esta entrega
Esta es una base de navegación y autenticación. Las pantallas de módulos aparecen en el panel, pero sus operaciones completas (CRUD de alumnos, cámara QR, captura manual, reportes y edición de horarios) aún deben desarrollarse. No es todavía una versión final de producción. No se ha compilado en el equipo Windows del usuario; ejecutar los comandos anteriores y reportar cualquier error.

## Registro manual y salidas (nuevo)
- Buscar por nombres, apellidos o DNI (desde 2 caracteres) con sugerencias.
- Tipo: Automático, Forzar entrada o Forzar salida. Motivo: 5 opciones + Otros (texto obligatorio).
- Salidas pendientes de hoy: cerrar una o todas (hora oficial del turno, tabla `horarios.hora_salida`) o marcar inasistencia.
- Entrada sin salida cerrada al terminar el día pasa a FALTA automáticamente.
- En el escáner QR, el segundo escaneo del día (pasados 10 min) registra la salida.
- La base de datos sube a versión 4 (migración automática).

## Escáner QR
- Menú lateral → **Escanear QR**. Funciona con cualquier cámara que Windows detecte (webcam integrada, USB, o virtual como DroidCam/Iriun para usar el celular). Si hay varias, se elige en el desplegable.
- Al leer un QR de estudiante se registra la asistencia (`tipo = QR`) y suena un beep (interruptor "Sonido al escanear"). Aviso grave si el código es inválido, el estudiante está deshabilitado o ya registró hoy.
- Estado: TEMPRANO si la hora es menor o igual a la hora límite del turno (tabla `horarios`); TARDE si la supera.
- Panel "Últimos registrados en esta sesión": estudiante, hora, tipo y estado.
- Sonidos en `assets/sounds/` (`ok.wav`, `warn.wav`); se pueden reemplazar por otros.
- Ejecutar `flutter pub get` tras actualizar. En Windows 10/11 permitir el acceso a la cámara a apps de escritorio (Configuración → Privacidad → Cámara).

## Reportes y Horarios (nuevo)
- **Exportar a Excel** usa el formato de la plantilla REG_DE_ASISTENCIA: una hoja por mes, semanas y días L-M-M-J-V, símbolos ✔ (1) / ✘ (0) / T (tardanza), y totales por alumno y por día con fórmulas. Institución, docente, curso y nivel se completan en Excel. El informe individual añade una hoja "Detalle" con horas de entrada y salida.
- Menú lateral (administrador) → **Reportes**, debajo de Registro manual.
  - **Informe individual**: buscar estudiante (nombre o DNI), elegir fechas y generar. Muestra días esperados, presentes, ausentes, puntuales, tardanzas, % de asistencia, salidas pendientes y el detalle por día.
  - **Reporte general**: periodo (Hoy, 7 días lectivos, Este mes, Rango personalizado), turno, grado, sección y estudiante opcional.
  - Ambos tienen **Exportar a Excel** (.xlsx con hoja de resumen y hoja de detalle).
  - Día esperado = día lectivo (lunes a viernes) con al menos un registro en el turno del estudiante.
- Menú lateral → **Horarios**: editar por turno la hora límite de entrada (TEMPRANO/TARDE) y la hora oficial de salida (tabla `horarios`).
