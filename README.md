# MetaPlayKit

Proyecto limpio de Godot 4.7 que moderniza los casos funcionales documentados
en `interfaces/`: inicio, carga asíncrona, selector de niveles, partida de
demostración, pausa, resultados, recompensas, configuración, tienda e IAP.

## Ejecutar

Abre `project.godot` con Godot 4.7 y ejecuta la escena principal. El proyecto
usa una resolución lógica de 1280 × 720 con escalado `canvas_items`.

## Arquitectura

- `scripts/core/meta_play_model.gd`: estado e invariantes de niveles, saldo,
  configuración y compras.
- `scripts/facade/ttp_gui_api.gd`: autoload y API pública compatible con el
  contrato legado.
- `scripts/demo/stage.gd`: demo navegable y composición de la interfaz.
- `scripts/demo/level.gd`: ciclo funcional del nivel de prueba.
- `scripts/components/`: fondo bloqueante, estrellas, lista desplazable y
  artículos de tienda reutilizables.
- `scripts/systems/resource_batch.gd`: carga asíncrona segura con la API de
  Godot 4, sin el hilo permanente de la versión original.
- `scripts/utilities/iap_adapter.gd`: frontera opcional con `GodotPayments` y
  simulación explícita para escritorio/editor.

## Recursos heredados

Los recursos visuales reutilizados se extrajeron de
`interfaces/testAddons` mediante `tools/extract_legacy_assets.py`. Esa carpeta
se conserva como referencia y `interfaces/.gdignore` impide que Godot intente
importar el proyecto 3.x archivado.

## Verificación

`tests/test_meta_play_model.gd` cubre las reglas del dominio y el ciclo del
nivel. Los archivos de `scenarios/` recorren la aplicación con entradas reales
y comprueban layout, navegación, compras internas y monetarias simuladas,
victoria, derrota, recompensas, configuración y pausa.
