import "comandos_service.dart";

/// Una fila de la verificación Robby + ALFA (como la tabla del modal Robby de la web).
class FilaRobby {
  final String log;
  final String nombreProceso;
  final String estado; // estado en Robby: OK, ERROR, Actualizando, Demorado...
  final String? fechaEjecucion; // ultima vez en la tabla de flujos ALFA
  final String? hora;
  final String? alfaProcesoPadre;
  final String? alfaRutaPadre;
  final String? alfaTipo;

  const FilaRobby({
    required this.log,
    required this.nombreProceso,
    required this.estado,
    this.fechaEjecucion,
    this.hora,
    this.alfaProcesoPadre,
    this.alfaRutaPadre,
    this.alfaTipo,
  });

  factory FilaRobby.fromJson(Map<String, dynamic> j) => FilaRobby(
        log: (j["log"] ?? "").toString(),
        nombreProceso: (j["nombre_proceso"] ?? "").toString(),
        estado: (j["estado"] ?? "").toString(),
        fechaEjecucion: _texto(j["fecha_ejecucion"]),
        hora: _texto(j["hora"]),
        alfaProcesoPadre: _texto(j["alfa_proceso_padre"]),
        alfaRutaPadre: _texto(j["alfa_ruta_padre"]),
        alfaTipo: _texto(j["alfa_tipo"]),
      );
}

/// `robby.verificar`: lo que muestra la web al consultar un proceso en Robby.
class VerificacionRobby {
  final String proceso;
  final List<FilaRobby> filas;
  final int robbyFilas;
  final int alfaFilas;
  final bool sinProcesoPadre;
  final String? robbyError;
  final String? alfaError;

  /// Nombre a insertar (el PROCESO_PADRE, no el LOG *_ALL).
  final String? sugerencia;
  final String? sqlInsert;

  const VerificacionRobby({
    required this.proceso,
    this.filas = const [],
    this.robbyFilas = 0,
    this.alfaFilas = 0,
    this.sinProcesoPadre = false,
    this.robbyError,
    this.alfaError,
    this.sugerencia,
    this.sqlInsert,
  });

  factory VerificacionRobby.fromJson(Map<String, dynamic> j) => VerificacionRobby(
        proceso: (j["proceso"] ?? "").toString(),
        filas: ((j["filas"] as List?) ?? const [])
            .whereType<Map>()
            .map((f) => FilaRobby.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
        robbyFilas: (j["robby_filas"] as num?)?.toInt() ?? 0,
        alfaFilas: (j["alfa_filas"] as num?)?.toInt() ?? 0,
        sinProcesoPadre: j["sin_proceso_padre"] == true,
        robbyError: _texto(j["robby_error"]),
        alfaError: _texto(j["alfa_error"]),
        sugerencia: _texto(j["sugerencia"]),
        sqlInsert: _texto(j["sql_insert"]),
      );

  /// Ya figura en la tabla de flujos ALFA.
  bool get enAlfa => alfaFilas > 0;
}

String? _texto(Object? v) {
  final s = v?.toString().trim() ?? "";
  return s.isEmpty ? null : s;
}

/// Lo mismo que el modal «Robby» de /procesos en la web, a través de OP_PROD.
/// Solo administradores (el backend lo exige): insertar escribe en Netezza.
class RobbyService {
  RobbyService({ComandosService? comandos}) : _comandos = comandos ?? ComandosService();

  final ComandosService _comandos;

  /// Solo letras, números, _, -, ., / y espacios (lo mismo que valida OP_PROD).
  static final nombreValido = RegExp(r"^[A-Za-z0-9_\-./ ]{1,500}$");

  Future<VerificacionRobby> verificar(String proceso) async {
    final r = await _comandos.ejecutar("robby.verificar", payload: {"proceso": proceso});
    return VerificacionRobby.fromJson(r.resultado);
  }

  /// INSERT en la tabla de flujos ALFA para que Robby lo ejecute.
  Future<String?> insertar(String nombreProceso, {String? titulo}) async {
    final r = await _comandos.ejecutar(
      "robby.insertar",
      payload: {"nombre_proceso": nombreProceso},
      titulo: titulo,
    );
    return r.resultado["insertado_en"]?.toString();
  }
}
