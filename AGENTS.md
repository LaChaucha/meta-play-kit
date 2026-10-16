# AGENTS.md — MetaPlayKit

## Propósito y alcance

MetaPlayKit es un addon reutilizable de Godot en desarrollo como producto orientado a producción: una capa de metajuego para integrar en varios juegos anfitriones. El repositorio contiene el addon y un consumidor de ejemplo con pantallas navegables, nivel simulado, recompensas, configuración y tiendas. El ejemplo demuestra integración; no define las responsabilidades del producto ni obliga a los anfitriones a usar sus pantallas.

El proyecto está hecho para Godot 4.7, con GDScript tipado y renderer GL Compatibility. La escena principal del consumidor de ejemplo es `res://demo/scenes/main.tscn`. El addon distribuible vive en `addons/metaplay_kit/`; `demo/` es solo una integración de referencia. El estado y las brechas del producto se describen en `PRODUCT.md` y se refinan en los issues de GitHub. La carpeta `interfaces/` y su antiguo `testAddons` son material de referencia: no forman parte del runtime y `.gdignore` impide importar el proyecto legado.

## Reglas para trabajar en este proyecto

- Mantén separadas las responsabilidades: `MetaPlayModel` aplica reglas y estado; `TtpGuiApi` expone el contrato y coordina; `MetaPlayDemoStage` compone el consumidor de ejemplo; los componentes reutilizables manejan piezas acotadas de UI.
- Antes de editar GDScript, consulta las convenciones de Godot 4 y conserva tipos explícitos en variables, argumentos y retornos. Evita inferir tipos desde `Variant`, diccionarios, nodos o valores nulos.
- Usa rutas `res://` para recursos del proyecto. Si mueves o renombras recursos, actualiza todas sus referencias y sidecars `.uid`/`.import` usando herramientas apropiadas de Godot.
- Construye la interfaz dinámica con contenedores. El tema global vive en `addons/metaplay_kit/assets/theme/metaplay.tres`; evita añadir sombras o overrides tipográficos generales sin comprobar su efecto en todo el proyecto.
- No conviertas la IAP simulada en una compra real ni abras enlaces externos automáticamente. La compra en escritorio es explícitamente una simulación; los enlaces se abren sólo por acción del usuario.
- `interfaces/testAddons` es referencia archivada. No copies su runtime de Godot 3 al proyecto actual ni elimines esa referencia sin una petición explícita.
- La implementación actual aún no incluye backend ni guardado persistente: modelo, progreso, saldo, ajustes y compras viven en memoria durante la sesión. No asumas que esta limitación define el alcance final; las opciones de producción se registran en `PRODUCT.md` y en el backlog. Mantén la IAP de escritorio como simulación salvo que se defina y autorice una integración de proveedor verificado.

## Desglose de épicas en historias de usuario

Cuando se solicite convertir una épica o issue de producto en historias de usuario:

- Analiza el alcance, problema, requisitos y criterios existentes en el issue antes de redactar. Contrasta el contrato actual del producto cuando sea necesario y distingue requisitos explícitos de decisiones propuestas.
- Agrupa las historias por módulo o componente del sistema y ordénalas en una secuencia que permita implementarlas y validarlas.
- Guarda la documentación bajo `tasks/`, con un `README.md` índice que enlace las historias, identifique la épica de origen y resuma decisiones relevantes y el orden sugerido.
- Usa archivos con el formato `US-XXX-short-descriptive-name.md`, con identificadores secuenciales que no sustituyan ni confundan el número del issue de GitHub.
- Cada historia debe incluir un título descriptivo y corto, módulo/componente, issue o épica relacionada, prioridad (`Alta`, `Media` o `Baja`) y una descripción en el formato: “Como [rol], quiero [acción] para [beneficio]”.
- Escribe criterios de aceptación verificables en formato BDD (“Dado que… Cuando… Entonces…”) o como lista de comprobación inequívoca. Cubre el flujo normal, errores y límites relevantes; evita criterios vagos o tareas técnicas que no describan un resultado observable.
- Mantén cada historia accionable y con alcance coherente. Divide capacidades independientes en historias distintas, declara dependencias o decisiones abiertas y, si una decisión de producto no está resuelta, marca claramente cualquier política recomendada como propuesta en lugar de requisito acordado.
- No crees commits ni hagas push al documentar historias salvo autorización explícita del usuario.

## Convención para commits

Cuando el usuario autorice crear un commit, usa esta línea con el nombre y correo indicados y reemplaza el mensaje vacío por una descripción breve y acorde con los cambios realizados:

```sh
GIT_AUTHOR_NAME="Eduardo David Angeleri" GIT_AUTHOR_EMAIL="angeleridavid@gmail.com" GIT_COMMITTER_NAME="Eduardo David Angeleri" GIT_COMMITTER_EMAIL="angeleridavid@gmail.com" git commit -m "<descriptive commit message>"
```

No crees commits ni hagas push sin autorización explícita del usuario.

## Estructura del proyecto

| Ruta | Responsabilidad |
| --- | --- |
| `project.godot` | Configuración de la demo, escena principal, autoload `TtpGuiApi` y tema. |
| `addons/metaplay_kit/plugin.cfg`, `plugin.gd` | Addon instalable; registra el autoload al habilitar el plugin. |
| `addons/metaplay_kit/runtime/api/ttp_gui_api.gd` | Contrato público, señales y coordinación del kit. |
| `addons/metaplay_kit/runtime/model/meta_play_model.gd` | Reglas y estado de niveles, monedas, tienda, artículos y configuración. |
| `addons/metaplay_kit/runtime/systems/resource_batch.gd` | Carga asíncrona de recursos. |
| `addons/metaplay_kit/runtime/components/` | Componentes de interfaz reutilizables. |
| `addons/metaplay_kit/runtime/ui/` | Fábrica UI y overlay de carga. |
| `addons/metaplay_kit/runtime/platform/iap_adapter.gd` | Frontera opcional de pagos y simulación de escritorio. |
| `addons/metaplay_kit/assets/` | Tema e iconos reutilizables del kit. |
| `PRODUCT.md` | Dirección del producto, límites de responsabilidad y criterios de preparación para producción. |
| `demo/scenes/`, `demo/scripts/` | Aplicación de ejemplo y nivel simulado consumidor del addon. |
| `demo/assets/`, `demo/tools/` | Recursos y utilidades exclusivos de la demo. |
| `tests/`, `scenarios/` | Pruebas del kit y recorridos funcionales de la demo. |
| `interfaces/` | Referencia archivada; no forma parte del runtime. |

## Inicialización y primer arranque

El orden en `MetaPlayDemoStage._ready()` es deliberado:

1. Configura el stage para procesar mientras el árbol está pausado.
2. Limpia nodos de scaffolding que no forman parte de la demo.
3. Construye la UI y obtiene referencias a pantallas, overlay, diálogo y etiquetas.
4. Conecta señales de `TtpGuiApi`, el modelo, la carga y el adaptador IAP.
5. Registra datos de demostración: seis niveles, saldo inicial, configuración, productos de moneda y catálogo de artículos.
6. Muestra el overlay y llama `TtpGuiApi.request_initial_level_load()`.

El primer nivel se carga e instancia, pero el primer arranque termina en inicio; no se entra directamente a la partida. Desde inicio, “Jugar” abre el nivel siguiente disponible. Los seis niveles de demostración apuntan a `level_stub.tscn`, pero conservan claves y datos de progreso distintos.

## Flujo de carga de niveles

La carga tiene una clave activa y una clave pendiente. `MetaPlayDemoStage._loading_level_key` identifica el destino que se está cargando; `_current_level_key` sólo cambia cuando el recurso se instancia correctamente.

1. La UI solicita `TtpGuiApi.request_level_load(key)` o una acción de fachada equivalente.
2. La fachada busca el nivel en el modelo, copia su definición y añade `key` al diccionario enviado a `loading_started`.
3. El stage guarda la clave pendiente, despausa el árbol, detiene el nivel actual, oculta el juego y muestra el overlay.
4. `ResourceBatch` solicita el recurso con `ResourceLoader.load_threaded_request`, actualiza progreso y obtiene el `Resource` cuando termina.
5. Al terminar, `ResourceBatch` libera la lista activa antes de emitir finalización. Esto permite cargar la misma escena otra vez (por ejemplo, al repetir o pasar de nivel).
6. La fachada emite `loading_completed`; el stage recupera los datos pendientes e intenta convertir el recurso en `PackedScene` e instanciarlo.
7. Sólo después de una instancia válida se reemplaza `CurrentLevel`, se configura con clave y stage anfitrión, se actualiza la clave activa y se llama `start_level()`.
8. Si la instancia falla, el stage muestra un aviso y vuelve a inicio sin presentar una partida falsa ni cambiar la clave activa.
9. El overlay completa su animación y el stage muestra inicio en el primer arranque o la pantalla de juego en cargas posteriores.

`ResourceBatch.get_resource(path)` consume la entrada lista de esa ruta: una segunda lectura inmediata devuelve `null`. Cada nueva carga debe volver a registrar la ruta con `add_resource_to_batch()` y llamar `start_loading()`. Ante error, `load_failed` llega a la fachada, que emite `action_rejected` y solicita volver a inicio.

## Flujo de juego, resultados y progresión

El nivel de prueba no implementa gameplay real; sus botones simulan los callbacks del juego anfitrión. `MetaPlayDemoLevel` sólo admite victoria/derrota mientras `active == true`. Al completar una, detiene el nivel y llama al stage.

- **Victoria:** el stage llama `TtpGuiApi.complete_level(...)`; el modelo valida la clave, actualiza estrellas/puntuación, acredita monedas y desbloquea el siguiente nivel. La fachada emite `navigation_requested("win", payload)` y el stage muestra estrellas, puntuación y recompensa.
- **Repetir:** la clave actual se carga de nuevo; el nivel anterior se detiene y se crea una instancia nueva.
- **Duplicar recompensa:** una espera visual simula el anuncio; se agregan monedas extra y se solicita cargar el siguiente nivel disponible.
- **Siguiente:** carga el nivel indicado por el resultado/progresión. La validación de carga asegura que la partida sólo se muestre tras una instancia válida.
- **Derrota:** `report_level_loss` detiene el nivel y presenta opciones de repetir, reanimar o volver a inicio. La derrota no elimina el nivel ni cambia su desbloqueo.
- **Reanimar:** la recompensa simulada llama a `revive_level`; el nivel actual vuelve a activo y se cierra el resultado.
- **Pausa:** la acción `pause` o Escape abre el diálogo y pausa el árbol. Continuar reanuda; volver a inicio despausa y muestra inicio.

## Flujos de UI y negocio

- **Inicio:** iniciar partida, selector, tienda, configuración y promoción.
- **Selector:** muestra niveles habilitados, mejor puntuación y estrellas; permite recorrer la lista habilitada y cargar la selección. El modelo rechaza niveles bloqueados.
- **Tienda de artículos:** presenta artículos básicos, equipables y progresivos por fases. Las compras validan saldo; el equipamiento de un grupo (por ejemplo, sombreros) es exclusivo. `store_changed` refresca la vista.
- **Tienda de moneda:** aceptar una oferta llama al adaptador IAP; en escritorio éste emite una compra simulada y el modelo acredita la cantidad configurada para ese producto.
- **Configuración:** alterna SFX y música en el modelo y refleja el estado en la UI. Es persistencia sólo en memoria.
- **Promoción/enlaces:** la vista de video es una previsualización local; los enlaces a términos, valoración o promoción se abren con `OS.shell_open` tras pulsar el botón correspondiente.
- **Notificaciones:** `action_rejected` muestra mensajes breves; `currency_balance_changed` actualiza los saldos visibles.

## Contrato de señales

`TtpGuiApi` es el punto de entrada para consumidores. El stage escucha `navigation_requested`, `level_load_started`, `level_load_completed`, `level_load_exit_animation_completed`, `loading_progress_changed`, `action_rejected`, `currency_balance_changed`, `store_catalog_changed` y señales de configuración/recompensas. El modelo y el cargador son detalles internos; los consumidores usan consultas de la fachada para obtener copias de los datos. Los nombres legacy se conservan como wrappers/señales de compatibilidad para el contrato de `interfaces/INT-85-TTP_GUI_API.md`.

Usa métodos de la fachada en lugar de modificar directamente campos del modelo desde componentes nuevos. La excepción actual es la UI de demo, que lee algunos datos de catálogo/configuración para presentarlos; las mutaciones pasan por métodos del modelo/fachada.

## Datos de demostración y claves

Las claves configuradas por `MetaPlayDemoStage._configure_demo_data()` son `level1` a `level6`. Cada definición de nivel usa `name`, `max_score`, `max_stars`, `scene_path` y `enabled`. El primer nivel inicia habilitado; completar un nivel actualiza sus récords y habilita la progresión siguiente.

El catálogo de artículos usa claves superiores de producto y, en productos por fases, rutas tipo `["power_boost", "phase1"]`. Conserva esa forma al consultar, comprar o equipar artículos anidados. Los productos monetarios se relacionan con sus cantidades mediante `configure_currency_rewards()`.

## Pruebas y recorridos funcionales

Las pruebas unitarias cubren invariantes del modelo y regresiones de carga. En particular, `tests/test_level_loading.gd` verifica que una misma escena consumida pueda cargarse de nuevo y que una escena inválida no deje la interfaz mostrando juego sin nivel válido.

Los escenarios son JSON de automatización reproducible:

| Escenario | Cobertura |
| --- | --- |
| `boot_check.json` | Arranque, interfaz inicial y captura. |
| `home_wide_check.json` | Inicio en viewport amplio. |
| `game_win_flow.json` | Victoria, recompensa duplicada, nivel 2, reintento, derrota, reanimación y avance al nivel 3. |
| `levels_flow.json` | Selector y carga de nivel. |
| `store_purchase_flow.json` | Compra/equipamiento de artículos. |
| `currency_purchase_flow.json` | Compra simulada de monedas. |
| `config_flow.json` | Alternancia de sonido y música. |
| `lose_reward_flow.json` | Derrota y recompensa de reanimación. |
| `pause_flow.json` | Pausa, reanudar y volver a inicio. |
| `promo_flow.json` | Vista promocional y controles asociados. |

Al cambiar carga, navegación o señales, extiende primero una prueba dirigida y el escenario del flujo afectado. No des por probado un nivel sólo por verificar su etiqueta: acciona también sus botones de victoria/derrota y sus transiciones.

## Comandos de verificación

Ejecuta desde la raíz del proyecto. El runtime disponible al momento de documentar es Godot 4.7.2. Ajusta las rutas de `python` y `--godot-bin` si el entorno usa otras ubicaciones.

```powershell
$env:PYTHONUTF8 = '1'
python 'C:\Users\edgam\.codex-personal\skills\godot\scripts\debug\lint_project.py' . --include-addons
python 'C:\Users\edgam\.codex-personal\skills\godot\scripts\test\run_tests.py' . --framework mini --strict
python 'C:\Users\edgam\.codex-personal\skills\godot\scripts\debug\smoke_scenes.py' . --seconds 2 --fuzz --fuzz-seed 20261015 --jobs 2 --warnings-as-errors
```

Los escenarios se ejecutan con `scripts/debug/run_scenario.py`, pasando el proyecto, el JSON correspondiente y `--godot-bin` con el ejecutable console de Godot. Ejecuta todos los JSON de `scenarios/` al modificar la navegación o componentes compartidos. Para validación completa, valida por separado `addons/metaplay_kit`, `demo` y `tests`; `interfaces/` contiene un proyecto legado archivado y no debe incluirse en una validación recursiva normal.

## Historial técnico relevante

- El arreglo de carga repetida limpia las rutas activas de `ResourceBatch` antes de notificar a los consumidores.
- La pantalla de juego se presenta sólo después de instanciar el `PackedScene`; una carga inválida vuelve al inicio.
- La sombra general de etiquetas está desactivada para mantener el texto nítido. La variación `TitleLabel` conserva una sombra pequeña y suave sólo para títulos.
- El escenario `game_win_flow.json` incluye acciones reales sobre nivel 2 para cubrir la regresión que antes quedaba oculta al comprobar únicamente la etiqueta.
