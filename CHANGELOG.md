# Changelog

Todas las novedades relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/).

## [2.0.0] - 2026-09-28

Auditoría completa del plugin: geometría, orientación de cajas, usabilidad y
normas eléctricas (NTC 2050 + RETIE, NEC, IEC 60364).

### Corregido
- **Los tubos ya no atraviesan muros, pisos ni techos.** Cada punto guarda la(s)
  cara(s) donde se hizo clic (dos en una esquina muro/piso, todas en un vértice)
  y el trazado se desplaza por segmento para quedar **sobre** las superficies
  (a la vista) o **dentro** de ellas (empotrada). Antes el tubo quedaba medio
  enterrado por defecto, los puntos sobre aristas no se desplazaban y en las
  esquinas solo se separaba de una de las dos caras.
- **Curvas sobre esquinas exteriores** (borde de viga, mesón, columna): el
  vértice se separa hasta que la curva libra la arista.
- **Edición**: mover, insertar o extender anclas perdía la superficie del punto y
  el tubo reconstruido se hundía en el muro; ahora se conserva. Una tubería
  movida o rotada se edita donde está (antes volvía a su posición original).
- **Orientación de las cajas**: la normal se lleva a coordenadas de mundo con
  escala no uniforme y **siempre apunta hacia la cámara**, así la tapa mira hacia
  afuera aunque las caras del modelo estén invertidas. Si la inferencia se
  engancha a una arista o vértice se usa la cara visible bajo el cursor (antes
  la caja quedaba acostada como en el piso).
- Las cajas de paso se montan en la **superficie real** (no a un radio de
  distancia), su lado largo sigue la tubería y en esquinas se separan del piso.
- El tubo termina **exactamente en la pared de la caja** por la que entra
  (antes apuntaba al centro de la caja y podía atravesarla).
- Se puede conectar a **cajas anidadas** (p. ej. las cajas de paso automáticas).
- El Administrador de extensiones mostraba siempre la versión **1.0.0**.
- Los radios de curvatura estaban documentados como "Other Bends" pero son la
  columna "One Shot and Full Shoe Benders" de la Tabla 2 (valores correctos).
- Diámetros exteriores de **IMC** corregidos según UL 1242.
- Alt en Windows abría la barra de menús: los cambios de modo usan
  **Ctrl (Win) / Option (Mac)**.

### Añadido
- **Perfiles de norma**: *NTC 2050 + RETIE (Colombia)*, *NEC* e *IEC 60364*.
- **Cajas de paso por grados de curva** (máx. 360° entre cajas, NEC/NTC
  358.26 / 342.26 / 344.26 / 352.26), en lugar de "cada N curvas".
- **Conductores**: circuito, sistema, calibre, aislamiento (THHN/THWN-2, THW,
  H07V) y tierra; **ocupación del tubo en vivo** (Cap. 9 Tablas 1, 4 y 5) con
  botón de **diámetro mínimo que cumple**; **código de colores** RETIE / NEC /
  IEC 60445; metros de cable en la lista de materiales.
- **Soportes (abrazaderas)** modelados y contados según 358.30 / 342.30 /
  344.30 / Tabla 352.30.
- **Revisión normativa** en la ventana de Materiales, con enlace "Ver en el
  modelo", y aviso al crear/editar una tubería.
- Columna **Norma** (norma de producto, RETIE 2024 Art. 2.3.29) en la lista y
  exportaciones.
- Tipo **PVC rígido métrico (IEC 61386-21)** y cajas **estándar** 2×4", 4×4",
  5×5" y octagonal. Codos por ángulo estándar (90°, 45°, 30°, 22.5°).
- **Herramienta de tubería**: vista previa del recorrido real, tramos que
  chocan en **rojo**, longitud y ángulo junto al cursor, **bloqueo de eje con
  flechas**, Shift para bloquear la inferencia y menú de **clic derecho**.
- **Herramienta de caja**: **vista previa 3D** con la tapa resaltada, **giro de
  90°** (Ctrl/Option/Tab o escribiendo el ángulo), instalación **empotrada** al
  ras y menú de clic derecho para cambiar de caja.
- **Edición**: menú de clic derecho por ancla, soltar un ancla sobre una caja
  para conectarla, **aplicar los ajustes actuales** a una tubería (cambiar
  tipo/diámetro/montaje) y aviso de cambios sin aplicar.

### Cambiado
- **Panel** rediseñado en secciones (Norma, Tubería, Curvas, Cajas,
  Conductores, Avanzado) con accesos directos; se ocultan las opciones que no
  aplican. La exportación CSV/HTML vive en la ventana de Materiales (sale del
  menú) y el cambio curva/codo sale de la barra (sigue en el menú, el panel,
  Ctrl/Option y el clic derecho).
- Pruebas de geometría con un stub de la API de SketchUp en CI.

## [1.9.0] - 2026-07-24

### Añadido
- **Novedades tras actualizar**: al abrir una versión nueva, el plugin muestra
  una ventana **"Novedades vX.Y.Z"** con el **changelog de esa versión** (una
  sola vez por versión). El changelog viaja **dentro del `.rbz`**, así se ve sin
  conexión.
- **"Acerca de"** es ahora una ventana con **botón "❤ Donar con PayPal"** (igual
  que en el repositorio) y acceso directo a **Buscar actualizaciones**.
- La ventana de Novedades también incluye el botón de donación.

## [1.8.0] - 2026-07-23

### Añadido
- **Auto-actualización desde GitHub Releases** (macOS/Windows, sin Extension
  Warehouse):
  - Comando **Extensiones → SKP E-Plumb → Buscar actualizaciones…**.
  - **Aviso automático** al iniciar (una vez al día, **desactivable** en
    *Ajustes → Actualizaciones*): consulta el último Release y avisa si hay una
    versión más nueva.
  - Al haber actualización puede **descargar e instalar** el `.rbz` con
    `Sketchup.install_from_archive`, o abrir la página de descarga.

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

[1.9.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.9.0
[1.8.0]: https://github.com/aa-eion/skp-e-plumb/releases/tag/v1.8.0
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
