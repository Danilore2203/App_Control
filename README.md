# App de Controles

Sistema de monitoreo de controles con alertas tipo alarma en el celular (Android + iOS),
compuesto por una API (FastAPI + MySQL) y una app movil (Flutter) que se comunican via Firebase
Cloud Messaging (FCM) para las notificaciones push.

## Estructura

```
backend/   API REST en FastAPI, conecta a tu MySQL existente
mobile/    App Flutter (Android + iOS)
```

## 1. Backend (API)

### Instalacion

```
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Editar `.env` con:
- `DATABASE_URL`: cadena de conexion a tu MySQL (`mysql+pymysql://usuario:password@host:3306/tu_bd`)
- `JWT_SECRET`: un secreto largo y aleatorio (para firmar los tokens de sesion)
- `INGEST_API_KEY`: otro secreto, lo va a usar el script/proceso que reporta el resultado de cada control
- `FIREBASE_CREDENTIALS_PATH`: ruta al JSON de la cuenta de servicio de Firebase (ver paso 2)

Los modelos de `Control`/`Alerta` en `app/models.py` son un punto de partida generico
(nombre, proceso, estado, resultado, fecha). Cuando tengas a mano el esquema real de tu
tabla de controles, los ajustamos para que coincida.

### Correr en desarrollo

```
uvicorn app.main:app --reload
```

La API queda en `http://localhost:8000`, con documentacion interactiva en `http://localhost:8000/docs`.

Al arrancar crea automaticamente las tablas que falten en tu base (`usuarios`, `controles`, `alertas`).
Para produccion conviene pasar a migraciones con Alembic mas adelante, pero para arrancar esto alcanza.

### Endpoints principales

- `POST /auth/register`, `POST /auth/login` — cuentas de usuario de la app
- `POST /auth/me/fcm-token` — la app guarda ahi su token de notificaciones push
- `GET /controles` — lista de controles (requiere sesion)
- `POST /controles` — ingesta de resultados (requiere header `X-API-Key`, la usa el script que corre tus controles). Si el `estado` viene en `"fallo"`, dispara la alerta push automaticamente.
- `GET /alertas` — historial de alertas del usuario logueado

## 2. Firebase (notificaciones push)

1. Crear un proyecto en https://console.firebase.google.com
2. Agregar una app Android (con el `applicationId` que uses en `mobile/android`) y descargar `google-services.json`
3. Agregar una app iOS (con el bundle id que uses en `mobile/ios`) y descargar `GoogleService-Info.plist`
4. En **Project Settings > Service Accounts**, generar una clave privada nueva: ese JSON es el que va en `FIREBASE_CREDENTIALS_PATH` del backend
5. En **Project Settings > Cloud Messaging > Apple app configuration**, subir la **APNs Authentication Key** de tu cuenta de Apple Developer (necesaria para que FCM pueda reenviar a iPhone)
6. Para el modo "alarma real" en iOS (que suene aunque el iPhone este en silencio), hay que solicitarle a Apple el entitlement **Critical Alerts** desde tu cuenta de Apple Developer. Mientras se aprueba (o si no se aprueba), las alertas usan **Time-Sensitive**, que ya rompe el modo Enfoque/No Molestar sin permiso especial. Una vez aprobado, poner `CRITICAL_ALERTS_ENABLED=true` en el `.env` del backend.

## 3. App movil (Flutter)

Requiere tener instalado el **Flutter SDK** (no esta instalado en esta maquina todavia):
https://docs.flutter.dev/get-started/install

```
cd mobile
flutter create .          # genera las carpetas android/ e ios/ sin tocar lib/ ni pubspec.yaml
flutter pub get
```

Despues:
- Copiar `google-services.json` a `mobile/android/app/`
- Copiar `GoogleService-Info.plist` a `mobile/ios/Runner/`
- Agregar un archivo de sonido para la alarma:
  - Android: `mobile/android/app/src/main/res/raw/alarma.mp3` (o `.ogg`)
  - iOS: `mobile/ios/Runner/alarma.caf`
- Ajustar `mobile/lib/config.dart` con la URL real de la API (en emulador Android, `10.0.2.2` apunta al localhost de la PC; en un celular fisico hay que usar la IP/dominio real del servidor)

Correr la app:

```
flutter run
```

### Que hace ya el esqueleto de la app

- Login / registro contra la API
- Dashboard con la lista de controles y su estado
- Pantalla de alertas (historial)
- Registro automatico del token de FCM contra el backend al iniciar sesion
- Canal de notificacion Android `alarmas_criticas` con sonido e importancia maxima
- Notificaciones locales en primer plano con `fullScreenIntent` (Android) e `interruptionLevel: timeSensitive` (iOS)

## Proximos pasos sugeridos

1. Pasarme el esquema real de tu tabla de controles para ajustar `app/models.py`
2. Definir como tu sistema actual (el que corre los controles) va a llamar a `POST /controles` — cron, script, trigger de MySQL, etc.
3. Instalar Flutter SDK para poder correr y ajustar la app en un emulador/celular
4. Crear el proyecto de Firebase y cargar las credenciales
