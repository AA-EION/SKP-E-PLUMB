# Changelog

Todas las novedades relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/).

## [1.3.1] - 2026-07-22

### Corregido
- **Cajas de paso (RETIE) montadas contra la superficie real**: ahora la caja
  se orienta con su **cara ancha trasera paralela** a la pared/piso/techo donde
  se dibujó (antes quedaba acostada y atravesando la pared). Para ello el
  trazado **captura el normal de la cara sobre la que se marca cada punto** y lo
  usa para orientar la caja; si el punto se marcó en el aire, se hace un
  **raycast** a la superficie más cercana y, en último caso, se usa vertical.
- Los normales se guardan en la tubería, así la **edición** conserva la
  orientación de las cajas.

## [1.3.0] - 2026-07-22

### Cambiado
- **Caja automática (RETIE) ahora interrumpe la tubería**: el tubo **llega a la
  caja**, se coloca la **terminación** (conector / contratuerca + bushing
  normal o de aterrizaje, según la opción) y la tubería **continúa al otro
  lado** con su propia terminación. La caja **reemplaza** esa curva (el cambio
  de dirección ocurre en la caja). Antes se colocaba solo como marcador.

### Corregido
- **Orientación de cajas en paredes verticales** (antes solo el piso quedaba
  bien): la base se construye explícitamente (profundidad → normal de la cara,
  eje +Y hacia arriba). Verificado con pruebas unitarias de la base ortonormal.

## [1.2.0] - 2026-07-22

### Añadido
- **Caja automática (RETIE)**: opción activable en Ajustes para colocar la caja
  seleccionada **tras cada N curvas** (por defecto 2) del trazado.
- La tubería se **grafica en tramos de stock reales**: cada tubo (≤ el largo de
  inventario) es una pieza independiente y visible, y la **unión (copla) queda
  montada sobre el empalme** (un tubo termina, empieza el otro, y encima queda
  la copla). Los codos prefabricados quedan como **pieza aparte** unida con una
  copla a cada lado.

### Cambiado
- El **BOM cuenta los tubos por pieza dibujada** (coincide con lo graficado) y
  muestra los metros totales como detalle.

### Corregido
- **Orientación de cajas**: la cara ancha (W×H) queda **plana sobre la
  superficie** donde se hace clic (el eje de profundidad se alinea al normal),
  en lugar de aparecer perpendicular.

## [1.1.2] - 2026-07-21

### Corregido
- **Colocación de cajas**: la tapa de la caja se creaba como cara coplanar
  sobre la cara superior del cuerpo, lo que en algunos casos abortaba la
  operación y no aparecía nada. Ahora la tapa se construye en un grupo anidado
  aislado y es tolerante a fallos.
- `place_box` ahora **aborta la operación y muestra el error** si algo falla
  (antes podía quedar en silencio), y valida la cara base.

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

[1.3.1]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.3.1
[1.3.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.3.0
[1.2.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.2.0
[1.1.2]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.2
[1.1.1]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.1
[1.1.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.0
[1.0.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.0.0
