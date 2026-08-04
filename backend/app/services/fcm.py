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


def enviar_alerta_push(
    fcm_token: str,
    titulo: str,
    cuerpo: str,
    critica: bool = True,
    es_demorado: bool = False,
    tipo: str = "alerta_critica",
) -> str:
    """Envia una alerta via FCM como mensaje de puros datos (sin `notification`),
    para que la app la reciba y construya ELLA MISMA la notificacion (con
    pantalla completa tipo alarma) en cualquier estado -primer plano, segundo
    plano o con la app cerrada-, en vez de depender de que Android la muestre
    sola (lo cual no permite pantalla completa).

    `tipo` es lo que la app usa para decidir COMO mostrarla ("alerta_critica"
    dispara pantalla completa si la guardia esta armada y en horario;
    "alerta_normal" es siempre una notificacion comun, sin importar guardia
    -para avisos que no ameritan alarma, como el fallo silencioso de
    incoherencia proceso/tabla).

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
            "tipo": tipo,
            "titulo": titulo,
            "mensaje": cuerpo,
            # La app decide el color de la pantalla de alarma con esto: mismo
            # sonido/urgencia para demorado y error, pero demorado se pinta
            # amarillo/naranja en vez de rojo (no es lo mismo un proceso que
            # se demoro que uno que fallo de verdad).
            "esDemorado": "true" if es_demorado else "false",
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


def enviar_resumen_push(fcm_token: str, titulo: str, cuerpo: str) -> str:
    """Resumen agregado de procesos NO core en error/demorado (ver
    revisar_resumen_no_core en poller.py): a diferencia de enviar_alerta_push,
    no dispara pantalla completa ni sonido de alarma en el celular -es solo
    informativa, como cualquier notificacion normal de la app."""

    inicializar_firebase()

    mensaje = messaging.Message(
        token=fcm_token,
        data={
            "tipo": "resumen_no_core",
            "titulo": titulo,
            "mensaje": cuerpo,
        },
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "5"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=titulo, body=cuerpo),
                    content_available=True,
                )
            ),
        ),
    )
    return messaging.send(mensaje)
