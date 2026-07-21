# Changelog

Todas las novedades relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/).

## [1.1.1] - 2026-07-21

### Corregido
- **Los diálogos (Ajustes / BOM) no abrían**: se usaba `Sketchup::HtmlDialog`
  cuando la clase correcta de la API es `UI::HtmlDialog`, lo que lanzaba
  `NameError: uninitialized constant Sketchup::HtmlDialog`. Ahora abren.
- Auditadas todas las referencias de la API (`Sketchup::*`, `UI::*`, `Geom::*`)
  para descartar otros namespaces incorrectos.

## [1.1.0] - 2026-07-21

### Añadido
- **Edición por anclas** de tuberías existentes (herramienta *Editar*): mover,
  insertar y borrar vértices, **extender** el trazado, cambiar curva↔codo por
  vértice, y **reconstruir** geometría y BOM. Cada tubería guarda su trazado y
  ajustes en un diccionario propio para poder reabrirse.
- Comando **Diagnóstico** (versión, Ruby, SketchUp, disponibilidad de
  HtmlDialog) que además abre Ajustes para verificar la UI.

### Cambiado
- Los diálogos registran sus callbacks **antes** de cargar el HTML y se
  centran al abrir; los errores ahora se muestran en un cuadro de diálogo en
  lugar de fallar en silencio.
- La barra de herramientas se muestra de forma fiable en la primera instalación.
- El empaquetado genera **un único** `SKP-E-Plumb.rbz` (antes se generaban dos).

### Corregido
- El método de unión de IMC/Galvanizado/PVC ya no depende de la opción de EMT.

### Removido
- El `.rbz` ya no se versiona dentro del repositorio; se publica solo en las
  Releases de GitHub.

## [1.0.0] - 2026-07-21

### Añadido
- Herramienta interactiva para dibujar canalizaciones eléctricas por clics.
- Soporte de tipos **EMT, IMC, Galvanizado (RMC) y PVC** con diámetros
  comerciales de 1/2" a 4" y diámetros exteriores reales por tipo.
- Uniones correctas por tipo: set-screw/compresión (EMT), roscado (IMC/RMC),
  cementado (PVC).
- Dos modos de curva alternables con `Alt`/`Option`: **doblar tubo** (curva de
  campo) y **codo prefabricado** (ítem separado del BOM).
- Radio de curvatura configurable con mínimos según **NEC Cap. 9, Tabla 2**.
- Coplas automáticas por tramo de stock; conteo de tubos = ⌈metros / tramo⌉.
- Terminaciones a cajas con **bushing aislante** y **bushing de aterrizaje**,
  contratuercas y conectores.
- Cajas **Plexo** (IP55) y **Rawelt** (condulets C/LB/LL/LR/T/X y cajas FS/FD).
- **BOM en vivo** derivado del modelo, con exportación a **CSV** y **HTML**.
- Diálogos `HtmlDialog` de Ajustes y BOM, barra de herramientas e íconos.
- Empaquetado `.rbz`, pruebas de lógica offline y flujo de publicación en CI.

[1.1.1]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.1
[1.1.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.0
[1.0.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.0.0
