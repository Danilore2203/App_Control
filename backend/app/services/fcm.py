import json

import firebase_admin
from firebase_admin import credentials, messaging

from app.config import settings

_firebase_app = None


def inicializar_firebase():
    global _firebase_app
    if _firebase_app is None:
        if settings.firebase_credentials_json:
            cred = credentials.Certificate(json.loads(settings.firebase_credentials_json))
        else:
            cred = credentials.Certificate(settings.firebase_credentials_path)
        _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def enviar_alerta_push(fcm_token: str, titulo: str, cuerpo: str, critica: bool = True) -> str:
    """Envia una alerta via FCM como mensaje de puros datos (sin `notification`),
    para que la app la reciba y construya ELLA MISMA la notificacion (con
    pantalla completa tipo alarma) en cualquier estado -primer plano, segundo
    plano o con la app cerrada-, en vez de depender de que Android la muestre
    sola (lo cual no permite pantalla completa).

    Si `critica` y CRITICAL_ALERTS_ENABLED estan activos, intenta usar el nivel
    Critical Alert de iOS (requiere el entitlement aprobado por Apple).
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
        data={
            "tipo": "alerta_critica",
            "titulo": titulo,
            "mensaje": cuerpo,
        },
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=titulo, body=cuerpo),
                    sound=apns_sound,
                    content_available=True,
                    custom_data={"interruption-level": interruption_level},
                )
            ),
        ),
    )
    return messaging.send(mensaje)
