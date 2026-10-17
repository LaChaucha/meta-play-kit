# AGENTS.md — MetaPlayKit

## Propósito y alcance

MetaPlayKit es un addon reutilizable de Godot en desarrollo como producto orientado a producción: una capa de metajuego para integrar en varios juegos anfitriones. El repositorio contiene el addon y un consumidor de ejemplo con pantallas navegables, nivel simulado, recompensas, configuración y tiendas. El ejemplo demuestra integración; no define las responsabilidades del producto ni obliga a los anfitriones a usar sus pantallas.

El proyecto está hecho para Godot 4.7, con GDScript tipado y renderer GL Compatibility. La escena principal del consumidor de ejemplo es `res://demo/scenes/main.tscn`. El addon distribuible vive en `addons/metaplay_kit/`; `demo/` es solo una integración de referencia. El estado y las brechas del producto se describen en `PRODUCT.md` y se refinan en los issues de GitHub. La carpeta `interfaces/` y su antiguo `testAddons` son material de referencia: no forman parte del runtime y `.gdignore` impide importar el proyecto legado.

## Reglas para trabajar en este proyecto

- Mantén separadas las responsabilidades: `MetaPlayModel` aplica reglas y estado; `TtpGuiApi` expone el contrato y coordina; `MetaPlayDemoStage` compone el consumidor de ejemplo; los componentes reutilizables manejan piezas acotadas de UI.
- Antes de editar GDScript, consulta las convenciones de Godot 4 y conserva tipos explícitos en variables, argumentos y retornos. Evita inferir tipos desde `Variant`, diccionarios, nodos o valores nulos.
- Usa rutas `res://` para recursos del proyecto. Si mueves o renombras recursos, actualiza todas sus referencias y sidecars `.uid`/`.import` usando herramientas apropiadas de Godot.
- Construye la interfaz dinámica con contenedores. El tema global vive en `addons/metaplay_kit/assets/theme/metaplay.tres`; evita añadir sombras o overrides tipográficos generales sin comprobar su efecto en todo el proyecto.
- Mantene la IAP de escritorio explicitamente simulada. `GooglePlayPurchaseProvider` verifica recibos firmados de Google Play cuando el anfitrion configura la clave publica de Play Console; otros mercados/verificadores se conectan mediante `PurchaseProviderAdapter`. La verificacion local no sustituye la verificacion server-side necesaria para detectar revocaciones y fraude. No abras enlaces externos automaticamente; solo por accion del usuario.
- `interfaces/testAddons` es referencia archivada. No copies su runtime de Godot 3 al proyecto actual ni elimines esa referencia sin una petición explícita.
- No hay backend ni guardado persistente automatico: modelo, progreso, saldo, ajustes y compras viven en memoria hasta que el anfitrion exporta y guarda el snapshot. El ledger local de transacciones evita repetir un abono dentro de un snapshot, pero no es autoridad frente a manipulacion del cliente. Los juegos online deben verificar y deduplicar tokens en su backend.

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
| `addons/metaplay_kit/runtime/ui/meta_play_ui_config.gd` | Perfil tipado y versionado de presentación para componentes reutilizables; se registra antes de instanciar la UI. |
| `addons/metaplay_kit/runtime/platform/iap_adapter.gd` | Frontera opcional de pagos y simulación de escritorio. |
| `addons/metaplay_kit/runtime/platform/purchase_provider_adapter.gd` | Contrato neutral de proveedores de compras. |
| `addons/metaplay_kit/runtime/platform/google_play_purchase_provider.gd` | Adaptador opcional Google Play, verificaci?n local de firma y consulta de compras restauradas. |
| `addons/metaplay_kit/assets/` | Tema e iconos reutilizables del kit. |
| `PRODUCT.md` | Dirección del producto, límites de responsabilidad y criterios de preparación para producción. |
| `demo/scenes/`, `demo/scripts/` | Aplicación de ejemplo y nivel simulado consumidor del addon. |
| `demo/assets/`, `demo/tools/` | Recursos y utilidades exclusivos de la demo. |
| `tests/`, `scenarios/` | Pruebas del kit y recorridos funcionales de la demo. |
| `interfaces/` | Referencia archivada; no forma parte del runtime. |

## Inicialización y primer arranque

El orden en `MetaPlayDemoStage._ready()` configura el consumidor antes de iniciar la carga:

1. Configura el stage para procesar mientras el árbol está pausado, limpia scaffolding y construye la UI.
2. Conecta señales de `TtpGuiApi`, el modelo, la carga y el adaptador IAP.
3. Registra el catálogo estático, las reglas de resultados por nivel, la proyección de campaña definida por el anfitrión, y los datos de tienda/configuración.
4. Muestra el overlay y llama `TtpGuiApi.request_initial_level_load("level1")` con destino explícito.

Un anfitrión que suministre `MetaPlayUIConfig` debe llamar `TtpGuiApi.configure_ui_presentation(profile)` antes de crear componentes reutilizables del kit. El primer componente bloquea la configuración para la sesión; las llamadas posteriores emiten advertencia y se ignoran. Los componentes capturan una copia al inicializarse. El kit conserva un perfil interno predeterminado y nunca modifica el recurso entregado por el anfitrión. Los valores incompatibles deben advertir por campo y usar el default correspondiente. El perfil tipado configura estilos, dimensiones/distribución, textos internos opcionales y los slots gráficos publicados por el kit. El idioma y los recursos los elige el anfitrión; los textos se pasan resueltos en `MetaPlayUITextConfig` y las texturas globales son campos `Texture2D` que aceptan recursos del proyecto anfitrión. Para iconos por artículo se usa `icon_path` con ruta `res://` validada al crear el botón. Los slots vacíos usan defaults del kit. No hay selector de idioma ni cambio en caliente en esta versión. El perfil no define la estructura de pantallas del anfitrión ni cambia su tema global.

La navegación y disponibilidad de pantallas pertenecen al anfitrión. `TtpGuiApi` expone resultados de dominio e intenciones de componentes reutilizables, pero no nombres de pantallas ni comandos para abrirlas. La demo implementa sus transiciones en `MetaPlayDemoStage`.

El primer nivel se carga e instancia, pero el primer arranque termina en inicio; no se entra directamente a la partida. La política de inicio y selección pertenece al anfitrión. Los seis niveles de demostración apuntan a `level_stub.tscn`, con claves y progreso distintos.

## Flujo de carga de niveles

`MetaPlayDemoStage._loading_operation_id` identifica la carga pendiente; la clave y el recurso de destino llegan juntos en el resultado. `_current_level_key` sólo cambia cuando el candidato se configura e inicia correctamente.

1. La UI solicita `TtpGuiApi.request_level_load(key)` o una acción de fachada equivalente. Cada solicitud aceptada recibe un `operation_id` monotónico; las solicitudes rechazadas no emiten eventos del ciclo de carga.
2. La fachada busca el nivel en el modelo, copia su definición y añade `key` al diccionario enviado a `loading_started`.
3. El stage guarda el ID de operación, usa los datos de inicio para mostrar la ruta en el overlay, despausa el árbol, detiene el nivel actual y oculta el juego.
4. `ResourceBatch` solicita el recurso con `ResourceLoader.load_threaded_request`, actualiza progreso y obtiene el `Resource` cuando termina.
5. Al terminar, `ResourceBatch` libera la lista activa antes de emitir finalización. Esto permite cargar la misma escena otra vez (por ejemplo, al repetir o pasar de nivel).
6. La fachada recupera el recurso de esa operación y emite `level_load_completed(operation_id, level_data, resource)`; el stage correlaciona el ID y convierte el recurso recibido en `PackedScene` para instanciarlo. Los fallos del cargador o un resultado sin recurso emiten `level_load_failed(operation_id, level_data, message)` y nunca éxito para el mismo ID.
7. El stage configura e inicia un candidato temporal. Sólo si ambos pasos tienen éxito reemplaza `CurrentLevel` y actualiza la clave activa.
8. Si la instancia falla, el stage muestra un aviso y vuelve a inicio sin presentar una partida falsa ni cambiar la clave activa.
9. El overlay completa su animación y el stage muestra inicio en el primer arranque o la pantalla de juego en cargas posteriores.

`ResourceBatch.get_resource(path)` consume la entrada lista de esa ruta: una segunda lectura inmediata devuelve `null`. Cada nueva carga debe volver a registrar la ruta con `add_resource_to_batch()` y llamar `start_loading()`. Ante error, `load_failed` llega a la fachada, que emite `action_rejected`; el anfitrión decide cómo recuperarse y qué pantalla presentar.

## Flujo de juego, resultados y progresión

El nivel de prueba no implementa gameplay real; sus botones simulan callbacks del juego anfitrión. `MetaPlayDemoLevel` sólo admite resultados mientras `active == true`.

- **Resultado:** el anfitrión envía `attempt_id`, puntuación, hechos booleanos para las condiciones configuradas y datos opcionales de presentación a `complete_level`. El kit exige que todas las condiciones requeridas sean verdaderas para ganar; aplica umbrales inclusivos de estrellas y permite una victoria con cero estrellas bajo el primer umbral. El modelo registra mejor puntuación/estrellas y no habilita ni elige niveles.
- **Siguiente nivel:** el anfitrión elige el destino según sus reglas y solicita `request_next_level_load(key)` o `request_level_load(key)` explícitamente.
- **Acciones del resultado:** `LevelResultPanel` es un componente opcional. Emite `terminal_action_requested(attempt_id, action_id)`; el anfitrión valida la oferta, aplica su efecto y deduplica reclamos. El kit no otorga premios opcionales ni aplica una política de cooldown para ellos.
- **Historial de campaña:** `LevelCampaignPanel` es opcional y representa la proyección que configura el anfitrión. La selección emite intención; el anfitrión la autoriza y comienza la carga.
- **Pausa:** la acción `pause` o Escape abre el diálogo y pausa el árbol. Continuar reanuda; volver a inicio despausa y muestra inicio.

## Flujos de UI y negocio

- **Inicio:** iniciar partida, selector, tienda, configuración y promoción.
- **Selector:** `LevelCampaignPanel` muestra la proyección de campaña que define el anfitrión junto con el progreso. La selección emite una intención; el anfitrión valida la política y solicita la carga explícita.
- **Tienda de artículos:** presenta artículos básicos, equipables y progresivos por fases. Las compras validan saldo; el equipamiento de un grupo (por ejemplo, sombreros) es exclusivo. `store_changed` refresca la vista.
- **Tienda de moneda:** aceptar una oferta llama al adaptador IAP; en escritorio éste emite una compra simulada y el modelo acredita la cantidad configurada para ese producto.
- **Configuración:** alterna SFX y música en el modelo y refleja el estado en la UI. Es persistencia sólo en memoria.
- **Promoción/enlaces:** la vista de video es una previsualización local; los enlaces a términos, valoración o promoción se abren con `OS.shell_open` tras pulsar el botón correspondiente.
- **Notificaciones:** `action_rejected` muestra mensajes breves; `currency_balance_changed` actualiza los saldos visibles.

## Contrato de señales

`TtpGuiApi` es el punto de entrada para consumidores. Las cargas exponen un `operation_id` monotónico en inicio, progreso y resultado terminal; las solicitudes rechazadas no emiten ciclo de vida, y cada aceptación termina exactamente una vez. El anfitrión autoriza la campaña, elige destinos y aplica/deduplica las acciones terminales recibidas por señal. `level_attempt_completed`, `level_selection_requested` y `terminal_action_requested` informan resultados o intenciones; el kit no emite órdenes para cambiar de pantalla ni aplica premios opcionales.

El perfil UI se configura con `configure_ui_presentation()` y se consulta con `get_ui_presentation_config()`. Esta configuración afecta solo componentes reutilizables del kit; las pantallas y controles propios siguen bajo control del anfitrión.

Los intentos de gameplay usan IDs distintos a las cargas. Los resultados identicos son idempotentes y los conflictos se rechazan. El snapshot version 4 incluye progreso, saldo, ajustes, inventario, recompensas base, ledger local de transacciones y estado serializable de features; excluye catalogo, reglas, presentacion y proyeccion de campana. El anfitrion configura estos datos antes de restaurar. Se migra solo la version 3 inmediatamente anterior; el anfitrion conserva el IO de guardado.

Usa métodos de la fachada en lugar de modificar directamente campos del modelo. La demo puede consultar proyecciones y datos para presentarlos; las mutaciones pasan por métodos de la fachada/modelo.

## Datos de demostración y claves

Las claves configuradas por `MetaPlayDemoStage._configure_demo_data()` son `level1` a `level6`. El catálogo contiene datos estáticos como `name` y `scene_path`; las reglas separadas contienen puntuación máxima, tres umbrales y condiciones requeridas. La proyección ordenada de campaña (`available` y `selectable`) la decide el anfitrión. El progreso contiene finalización, mejor puntuación y estrellas, sin autoridad para desbloquear niveles.

El catálogo de artículos usa claves superiores de producto y, en productos por fases, rutas tipo `["power_boost", "phase1"]`. Conserva esa forma al consultar, comprar o equipar artículos anidados. Los productos monetarios se relacionan con sus cantidades mediante `configure_currency_rewards()`.

## Pruebas y recorridos funcionales

Las pruebas unitarias cubren invariantes del modelo y regresiones de carga. En particular, `tests/test_level_loading.gd` verifica que una misma escena pueda cargarse de nuevo tras éxito, fallo o cancelación, con IDs y recursos correctos, y que una escena inválida no deje la interfaz mostrando juego sin nivel válido.

Los escenarios son JSON de automatización reproducible:

| Escenario | Cobertura |
| --- | --- |
| `boot_check.json` | Arranque, interfaz inicial y captura. |
| `home_wide_check.json` | Inicio en viewport amplio. |
| `game_win_flow.json` | Victoria, recompensa opcional del anfitrión, selección explícita del siguiente nivel, reintento, derrota y reanimación. |
| `levels_flow.json` | Proyección de campaña, intención de selección y carga explícita. |
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
- Un nuevo lote que solicita una ruta aún activa en el loader threaded se une a esa carga; los fallos invalidan el lote antes de emitir el resultado terminal.
- La pantalla de juego se presenta sólo después de instanciar el `PackedScene`; una carga inválida vuelve al inicio.
- La sombra general de etiquetas está desactivada para mantener el texto nítido. La variación `TitleLabel` conserva una sombra pequeña y suave sólo para títulos.
- El escenario `game_win_flow.json` incluye acciones reales sobre nivel 2 para cubrir la regresión que antes quedaba oculta al comprobar únicamente la etiqueta.
