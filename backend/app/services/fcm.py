import firebase_admin
from firebase_admin import credentials, messaging

from app.config import settings

_firebase_app = None


def inicializar_firebase():
    global _firebase_app
    if _firebase_app is None:
        cred = credentials.Certificate(settings.firebase_credentials_path)
        _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def enviar_alerta_push(fcm_token: str, titulo: str, cuerpo: str, critica: bool = True) -> str:
    """Envia una notificacion via FCM. Si `critica` y CRITICAL_ALERTS_ENABLED estan activos,
    intenta usar el nivel Critical Alert de iOS (requiere el entitlement aprobado por Apple).
    Mientras tanto, usa Time-Sensitive, que no requiere aprobacion especial."""

    inicializar_firebase()

    usar_critical = critica and settings.critical_alerts_enabled

    apns_sound = (
        messaging.CriticalSound(name="alarma.caf", critical=True, volume=1.0)
        if usar_critical
        else "alarma.caf"
    )
    interruption_level = "critical" if usar_critical else "time-sensitive"

    mensaje = messaging.Message(
        token=fcm_token,
        notification=messaging.Notification(title=titulo, body=cuerpo),
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="alarmas_criticas",
                sound="alarma",
                priority="max",
                visibility="public",
            ),
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound=apns_sound,
                    content_available=True,
                    custom_data={"interruption-level": interruption_level},
                )
            )
        ),
    )
    return messaging.send(mensaje)
