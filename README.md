# Centinela DWH (App de Controles)

Monitoreo de los procesos y tablas del DWH con alarmas tipo despertador en el
celular (Android + iOS). API en FastAPI + PostgreSQL, app en Flutter, y
Firebase Cloud Messaging (FCM) para las notificaciones push.

## Cómo fluyen los datos

```
OP_PROD (red Nuevatel) ──MySQL c137 (como siempre)
        │
        └──HTTPS 443──► POST /internal/catalogos ──► PostgreSQL de App_Control
                            │                                  │
                            ├─► ciclo del poller (alarmas, bitácora)
                            └─► FCM "catalogos_actualizados" ──► la app refresca
```

1. **OP_PROD** corre su snapshot cada 5 min y actualiza sus catálogos en MySQL
   *en el lugar* (una fila por proceso y día, id estable; cada cambio de
   estado queda como evento en `dataops_catalogo_cambios`).
2. Al terminar, **empuja a esta API solo lo que cambió** en ese ciclo
   (`backend/modules/dataops_monitor/push_app_control.py` en OP_PROD). Si no
   hubo cambios no manda nada; si falla la red, el próximo ciclo manda el día
   completo. La red de Nuevatel solo deja salir HTTPS, por eso no se escribe
   directo en la base.
3. La API aplica el envío (upsert por id, idempotente), corre un ciclo del
   poller y avisa a los celulares con un mensaje FCM silencioso.
4. La app **no sondea**: refresca cuando llega ese aviso y al volver a primer
   plano. El servicio de Guardia revisa cada 5 min como respaldo.

No existe réplica de tablas ni sondeo cada minuto: antes eso agotó la cuota
de consultas del plan gratuito de Supabase.

## Estructura

```
backend/   API REST (FastAPI + SQLAlchemy), desplegada en Railway
mobile/    App Flutter (Android + iOS)
```

## 1. Backend (API)

### Instalación

```
cd backend
uv venv .venv --python 3.12        # o: python -m venv .venv
uv pip install --python .venv\Scripts\python.exe -r requirements.txt pytest
copy .env.example .env
```

Variables de `.env` (en Railway van como variables del servicio):

- `DATABASE_URL`: PostgreSQL, p.ej. `postgresql+psycopg://usuario:password@host:5432/defaultdb?sslmode=require`
  (plan gratuito de Aiven; cualquier Postgres sirve, el código no usa nada
  propio de un proveedor).
- `JWT_SECRET`: secreto largo y aleatorio para firmar los tokens de sesión.
- `INTERNAL_API_KEY`: clave compartida con OP_PROD (allá es
  `OP_APP_CONTROL_INTERNAL_KEY`) para `/internal/*`.
- `FIREBASE_CREDENTIALS_PATH` o `FIREBASE_CREDENTIALS_JSON`: cuenta de servicio de Firebase.
- `MONITOR_AUTH_URL`: URL del monitor web de OP_PROD (login AD y pantalla de Infraestructura).
- `GOOGLE_OAUTH_CLIENT_ID`: Web client id de Firebase para el login con Google.
- `CRITICAL_ALERTS_ENABLED`: `true` solo cuando Apple apruebe el entitlement Critical Alerts.

### Correr y probar

```
.venv\Scripts\python.exe -m uvicorn app.main:app --reload
.venv\Scripts\python.exe -m pytest tests -q
```

La API queda en `http://localhost:8000` (documentación en `/docs`). Al
arrancar crea las tablas que falten y agrega las columnas nuevas
(idempotente). Las pruebas corren contra SQLite en memoria, no necesitan base.

### Endpoints principales

- `POST /internal/catalogos` — recibe los cambios de OP_PROD (header `X-Internal-Key`). Contrato en `app/schemas.py` (`CatalogoPushIn`) y lógica en `app/services/catalogos.py`.
- `POST /internal/solicitudes-registro/{id}/aprobar` — OP_PROD aprueba una cuenta local.
- `POST /auth/login`, `/auth/google`, `/auth/register` — sesión (AD vía OP_PROD, Google, o cuenta local aprobada por un admin).
- `POST /auth/me/fcm-token` — la app guarda su token de push.
- `GET /controles` — estado actual de cada proceso; `GET /controles/historial-fallas?dias=7` — procesos que fallaron por día.
- `GET /alertas` — historial de alertas; `/bitacora` — bitácora de errores; `/infra/*` — proxy al monitor de OP_PROD.

### El ciclo del poller (`app/services/ciclo.py`)

Se dispara al recibir cada push y, como respaldo, cada 5 min. En orden:
alarmas de procesos core según el estado actual, resumen horario de no-core,
bitácora a partir de los eventos de cambio (cursor `ultimo_cambio_revisado`),
resincronización de episodios abiertos y purga diaria (catálogos 60 días,
eventos y alertas 180). Un advisory lock de Postgres evita que dos instancias
corran a la vez durante un redeploy.

## 2. Firebase (notificaciones push)

1. Proyecto en https://console.firebase.google.com con una app Android
   (`com.nuevatel.controles`) y una iOS (mismo bundle id); descargar
   `google-services.json` y `GoogleService-Info.plist`.
2. **Project Settings > Service Accounts**: generar una clave privada; ese JSON
   va en `FIREBASE_CREDENTIALS_PATH` / `FIREBASE_CREDENTIALS_JSON`.
3. **Cloud Messaging > Apple app configuration**: subir la APNs Authentication Key.
4. Para alarma real en iOS con el celular en silencio hace falta el entitlement
   **Critical Alerts** de Apple; mientras tanto se usa Time-Sensitive.

Mensajes que manda el backend (todos de solo datos, la app arma la notificación):
`alerta_critica` (alarma de pantalla completa si la guardia está armada),
`alerta_normal`, `resumen_no_core` y `catalogos_actualizados` (silencioso, solo
refresca pantallas).

## 3. App móvil (Flutter)

```
cd mobile
flutter pub get
flutter run
```

- `google-services.json` en `mobile/android/app/`, `GoogleService-Info.plist` en `mobile/ios/Runner/`.
- `mobile/lib/config.dart` tiene la URL de la API.
- `flutter analyze` y `flutter test` corren en CI; no hace falta tener el SDK en la máquina para tocar el backend.

## 4. Lado OP_PROD

En `backend/config/secrets.local.env` de OP_PROD (máquina con
`OP_SCHEDULER_PRIMARY=1`, que es la que corre el snapshot):

```
OP_APP_CONTROL_URL=https://<dominio-de-railway>
OP_APP_CONTROL_INTERNAL_KEY=<la misma INTERNAL_API_KEY>
```

Sin esas dos variables el snapshot funciona igual pero no empuja nada.
