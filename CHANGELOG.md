# Changelog

Todas las novedades relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/).

## [1.7.0] - 2026-07-23

### Añadido
- **Montaje sobrepuesto en pared** (Ajustes → *Montaje del tubo → Sobrepuesto en
  pared*): al activarlo, el tubo se **desplaza hacia afuera** por el normal de la
  superficie donde se dibujó (≈ el radio del tubo), quedando **apoyado sobre** la
  pared/piso/techo en vez de medio enterrado. Se conserva al editar (el trazado
  original se guarda sin el offset para no acumularlo).

## [1.6.0] - 2026-07-23

### Añadido
- **Editar el tipo de nodo** en modo edición: con el cursor sobre un ancla,
  **Alt / Option cicla** ese nodo entre **curva de campo → codo prefabricado →
  caja**. Un nodo marcado como **caja** inserta una **caja de paso** ahí (con
  terminación a ambos lados), incluso en tramos rectos. Las anclas se colorean
  por tipo: **azul** = curva, **verde** = codo, **naranja** = caja.
- Junto con **insertar vértices** (clic en un segmento) y **extender** (clic en
  vacío), permite **añadir y cambiar elementos** de un tramo con facilidad.

## [1.5.0] - 2026-07-23

### Añadido
- **Conexión de tubería a caja (snap)**: al dibujar, si el cursor pasa sobre una
  **caja del plugin** (de nivel superior), la tubería hace **snap** a ella (se
  resalta el punto) y al hacer clic se **conecta**: el tubo llega a la **cara
  correcta** de la caja según por dónde entra y se coloca la **terminación**.
  - Una misma caja puede **recibir varias tuberías** (incluso de distinto
    diámetro): cada tubería se conecta por separado.
  - En un **paso recto que atraviesa la caja**, el tubo **entra por una cara y
    sale por la opuesta** ("por detrás" en cajas montadas en muro), cubriendo el
    caso de **caja a cada lado de un muro**.
  - Las conexiones se guardan por `persistent_id`, así se conservan al **editar**
    la tubería y entre guardados del modelo.

## [1.4.0] - 2026-07-22

### Añadido
- **Cursores propios por herramienta** (tubería / caja / edición) para ver
  claramente qué modo del plugin está activo.
- **BOM con dos modos de conteo de tubos**, seleccionables en el diálogo:
  - **Por tramos cortados** — cada pieza dibujada cuenta como un tubo.
  - **Optimizado (recorrido total)** — suma **todos** los metros del mismo
    tipo/medida en el modelo y calcula tubos = ⌈total / tramo⌉, reutilizando
    retazos entre tramos. Siempre se muestran los metros totales.

### Corregido
- **Orientación de cajas sobre caras dentro de grupos/componentes**: el normal
  de la cara ahora se transforma a **coordenadas de mundo**. Antes las cajas
  quedaban mal en paredes que son grupos (y bien en el piso), porque se usaba el
  normal en coordenadas locales del grupo.

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

[1.7.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.7.0
[1.6.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.6.0
[1.5.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.5.0
[1.4.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.4.0
[1.3.1]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.3.1
[1.3.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.3.0
[1.2.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.2.0
[1.1.2]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.2
[1.1.1]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.1
[1.1.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.1.0
[1.0.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.0.0
