# SKP E-Plumb — Modelador de canalizaciones eléctricas + BOM para SketchUp

[![Donar con PayPal](https://img.shields.io/badge/Donar-PayPal-0070BA?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=juanesgtgt2%40gmail.com&no_recurring=0&item_name=Apoyo%20a%20SKP%20E-Plumb&currency_code=USD)
[![Licencia: GPL-3.0](https://img.shields.io/badge/Licencia-GPL--3.0-blue)](LICENSE)

**SKP E-Plumb** es una extensión para **SketchUp** (2019 o posterior, probada
para **SketchUp 2026** en **macOS** y **Windows**) para dibujar
**canalizaciones eléctricas** sobre muros, pisos y techos, **revisarlas contra
la norma** (**NTC 2050 + RETIE**, **NEC** o **IEC 60364**) y generar la
**lista de materiales**: tubos por tramo comercial, uniones, codos, conectores,
boquillas, soportes, cajas y **conductores** con su código de colores.

> ⚡ *Herramienta de modelado, estimación y apoyo a la revisión. No sustituye el
> diseño ni el cálculo de un profesional, ni la inspección de la instalación
> (RETIE / autoridad local).*

- Licencia: **GPL-3.0-or-later**
- Versión: **2.0.0**
- Formato de instalación: **`.rbz`**

---

## ✨ Características

- **El tubo se apoya en las superficies, no las atraviesa.** Cada punto recuerda
  la(s) cara(s) sobre la(s) que se hizo clic (dos en una esquina muro/piso) y
  todo el trazado se desplaza para quedar **sobre** muros, pisos y techos
  (*a la vista*) o completamente **dentro** de ellos (*empotrada*). Sobre una
  **esquina exterior** (borde de viga, columna, mesón) el vértice se separa hasta
  que la curva libra la arista.
- **Aviso de choques en vivo**: mientras dibujas, el tramo que atravesaría un
  objeto se pinta en **rojo** y lo indica el texto junto al cursor.
- **Cajas bien orientadas**: la tapa siempre mira hacia ti (aunque las caras del
  modelo estén invertidas o dentro de grupos escalados), el fondo queda contra
  la superficie (o empotrada al ras) y el lado largo de las conduletas sigue la
  tubería. **Vista previa 3D** de la caja antes de colocarla y **giro de 90°**
  con Ctrl/Option/Tab.
- **Conexión a cajas**: pasa el cursor sobre una caja (también las de paso
  automáticas) y la tubería llega **exactamente a su pared** con la terminación
  correcta; un tubo que atraviesa la caja entra por una cara y sale por la otra.
- **Perfiles de norma** — *NTC 2050 + RETIE (Colombia)*, *NEC (EE.UU.)* e
  *IEC 60364*:
  - **Curvas entre cajas** (NEC/NTC 358.26, 342.26, 344.26, 352.26: máx.
    **360°**) con **cajas de paso automáticas** opcionales al superar el límite.
  - **Ocupación de conductores** (Cap. 9 Tabla 1: 53 % / 31 % / 40 %) con
    áreas reales de tubos (Tabla 4) y conductores THHN/THWN-2, THW (Tabla 5) o
    H07V (IEC 60227-3), y botón de **diámetro mínimo que cumple**.
  - **Soportes (abrazaderas)** modelados y contados: a ≤ 0.9 m de cada caja y
    cada ≤ 3 m (EMT/IMC/RMC) o según la Tabla 352.30 (PVC).
  - **Radio de curvatura** mínimo (Cap. 9 Tabla 2).
  - **Código de colores** de conductores: RETIE, NEC 200.6/250.119 o IEC 60445.
  - **Norma de producto** en la lista de materiales (RETIE 2024 Art. 2.3.29):
    NTC 105 (EMT), NTC 169 (IMC), NTC 171 (RMC), NTC 979 (PVC), IEC 61386…
- **Revisión normativa**: la ventana de Materiales lista, por tubería, lo que no
  cumple (curvas > 360°, sobre-ocupación, radio menor al mínimo, tramos largos
  sin registro en IEC) con un enlace para **verla en el modelo**.
- **Conductores en la lista de materiales**: metros por calibre, aislamiento y
  color (longitud del trazado + 0.2 m por caja).
- **Inventario / tramo de stock**: cada tubo comercial se dibuja como una pieza
  con su unión, y el conteo puede hacerse por piezas o **optimizado**.
- **Curvas: doblar el tubo o codo prefabricado** (Ctrl/Option en vivo). Los
  codos se cuentan por ángulo estándar (90°, 45°, 30°, 22.5°) y se marcan los
  no estándar.
- **Uniones correctas por tipo**: EMT set-screw o compresión; IMC/RMC
  roscado con contratuerca + boquilla; PVC cementado con adaptador terminal.
- **Edición por anclas**: mover, insertar, borrar, extender, cambiar el tipo de
  ancla (curva/codo/caja) y **aplicar los ajustes actuales** (p. ej. cambiar el
  diámetro de una tubería existente). Funciona aunque la tubería se haya movido.
- **Panel único y claro**: norma, tubería, curvas, cajas, conductores y
  avanzado; las opciones que no aplican se ocultan (p. ej. uniones solo en EMT).

---

## 🧱 Tipos de canalización

| Tipo | Norma de producto | Unión | Terminación en caja | Artículo NEC/NTC |
|------|-------------------|-------|---------------------|------------------|
| **EMT** | NTC 105 / UL 797 | Set-screw o compresión | Conector + boquilla | 358 |
| **IMC** | NTC 169 / UL 1242 | Roscada | Contratuerca + boquilla | 342 |
| **RMC** (galvanizado) | NTC 171 / UL 6 | Roscada | Contratuerca + boquilla | 344 |
| **PVC** Sch-40 | NTC 979 / UL 651 | Cementada | Adaptador terminal + contratuerca | 352 |
| **PVC métrico** | IEC 61386-21 | Cementada | Adaptador terminal | — |

Medidas comerciales `1/2"` … `4"` (Ø exteriores reales por tipo) y métricas
Ø16 … Ø63 mm. Cajas: **estándar** (2×4", 4×4", 5×5", octagonal), **Plexo**
(IP55) y **Rawelt** (conduletas C, LB, LL, LR, T, X y cajas FS/FD).

---

## 📦 Instalación

1. Descarga **`SKP-E-Plumb.rbz`** desde la
   [última Release](../../releases/latest). El `.rbz` se publica únicamente en
   las Releases (no se versiona dentro del repositorio).
2. En SketchUp: **Ventana → Administrador de extensiones → Instalar extensión…**
   (*Window → Extension Manager → Install Extension…*).
3. Selecciona el `.rbz` y confirma.
4. Aparecerá el menú **Extensiones → SKP E-Plumb** y su **barra de herramientas**.
   Si no ves algo, usa **Extensiones → SKP E-Plumb → Diagnóstico…** para
   comprobar la carga.

> Compatible con SketchUp 2019 en adelante (usa `HtmlDialog`), probado para
> **SketchUp 2026** en macOS y Windows.

### Actualizaciones

El plugin puede **auto-actualizarse desde los Releases de GitHub** (macOS y
Windows):

- **Extensiones → SKP E-Plumb → Buscar actualizaciones…** consulta la última
  versión y, si hay una nueva, ofrece **descargar e instalar** el `.rbz`
  automáticamente (`Sketchup.install_from_archive`) o abrir la página.
- Un **aviso automático** (1×/día) revisa si hay novedades; se puede desactivar
  en *Panel → Avanzado*.
- Tras instalar una versión nueva, aparece una ventana **"Novedades"** con el
  changelog de esa versión. En **Acerca de** hay un botón **Donar con PayPal**.

> La auto-actualización *gestionada por el Administrador de extensiones* de
> SketchUp requiere publicar en el **Extension Warehouse** (y firma de Trimble).
> Este mecanismo propio no la sustituye, pero cumple la misma función sin el
> Warehouse.

---

## 🚀 Uso rápido

1. Abre el **Panel** (ícono de engranaje) y elige la **norma**, el **tipo** y
   **diámetro** de tubo, la **instalación** (*a la vista* o *empotrada*) y,
   si quieres, los **conductores** del circuito (verás la ocupación en vivo).
2. **✏️ Tubería**: haz **clic sobre muros, pisos y techos** para marcar el
   trazado. La línea azul muestra por dónde irá realmente el tubo.

   | Acción | Cómo |
   |--------|------|
   | Punto / conectar a caja | **Clic** (sobre una caja = conectar) |
   | Crear la tubería | **Doble clic** o **Enter** |
   | Deshacer último punto | **Retroceso** |
   | Curva ↔ codo para la próxima esquina | **Ctrl** (Win) / **Option** (Mac) |
   | Bloquear eje rojo / verde / azul | **→ / ← / ↑** (↓ desbloquea) |
   | Bloquear la inferencia | mantener **Shift** |
   | Distancia exacta | escribe la longitud y **Enter** |
   | Más opciones (caja en el último punto…) | **clic derecho** |

3. **▣ Caja**: mueve el cursor sobre una superficie — la vista previa muestra
   la caja con la **tapa resaltada** — y haz clic. **Ctrl/Option/Tab** gira 90°;
   clic derecho para cambiar de caja.
4. **☰ Materiales**: lista de materiales, pestaña **Revisión normativa** y
   exportación a **CSV** o **HTML**.

### Editar una tubería existente

Pulsa **✎ Editar** y haz clic en una tubería:

| Acción | Cómo |
|--------|------|
| Mover un ancla | **Arrastra** (suéltala sobre una caja para conectarla) |
| Insertar un ancla | **Clic sobre un segmento** |
| Extender | **Clic fuera** del trazado (se agrega al extremo más cercano) |
| Borrar un ancla | cursor sobre el ancla + **Retroceso/Supr** |
| Tipo de ancla (curva → codo → caja) | cursor sobre el ancla + **Ctrl/Option** |
| Cambiar tipo/diámetro/montaje | clic derecho → **Aplicar ajustes actuales** |
| Aplicar | **Enter** |

---

## 🧮 Cómo se calcula la lista de materiales

Cada pieza lleva metadatos (diccionario `SKP_E_PLUMB`) y cada tubería guarda su
trazado, superficies, opciones, conductores y estadísticas
(`SKP_E_PLUMB_RUN`). La lista se **deriva del modelo**.

- **Tubería**: por tramos dibujados (1 pieza = 1 tubo) u **optimizado**
  (⌈metros totales / tramo⌉ por tipo y medida).
- **Uniones**: una en cada empalme de tubos y dos por codo prefabricado.
- **Codos**: por ángulo estándar; las **curvas de campo** suman metros de tubo.
- **Terminaciones**: conector/contratuerca + boquilla aislante o de puesta a
  tierra según el tipo.
- **Soportes**: según el espaciamiento de la norma (instalación a la vista).
- **Cajas** y **conductores** (metros por calibre/aislamiento/color).
- Columna **Norma** con la norma de producto de cada ítem.

---

## 🛠️ Compilar y probar

Requisitos: `ruby` (3.x) y `zip`.

```bash
ruby tools/make_icons.rb     # íconos PNG (opcional, ya vienen incluidos)
./tools/build_rbz.sh         # empaqueta dist/SKP-E-Plumb.rbz
ruby tools/test_logic.rb     # catálogo, normas, ocupación, BOM, geometría pura
ruby tools/test_builder.rb   # geometría completa sobre un stub de la API de SketchUp
```

```
skp_e_plumb.rb            # Registro de la extensión (raíz del .rbz)
skp_e_plumb/
  main.rb                 # Carga módulos, menú y barra de herramientas
  catalog.rb              # Tipos, medidas, Ø, áreas, radios, cajas, normas de producto
  codes.rb                # Perfiles NTC 2050+RETIE / NEC / IEC: ocupación, soportes, colores, revisión
  geom_util.rb            # Geometría (tubos, arcos, cajas, desplazamiento sobre superficies)
  builder.rb              # Trazado -> geometría + metadatos + estadísticas
  picker.rb               # Superficie bajo el cursor (normales en mundo, hacia la cámara)
  bom.rb                  # Lista de materiales, revisión normativa, CSV/HTML
  settings.rb             # Preferencias persistentes (con migración desde 1.x)
  conduit_tool.rb / box_tool.rb / edit_tool.rb   # Herramientas interactivas
  ui_dialogs.rb           # Panel, Materiales, Acerca de, Novedades
  updater.rb              # Actualización desde GitHub Releases
tools/                    # Build, íconos, pruebas y stub de la API
```

---

## ⚠️ Limitaciones

- La geometría es **representativa** (Ø reales, arcos segmentados); no modela
  roscas ni el interior del tubo.
- La ocupación usa las tablas NEC/NTC 2050 Cap. 9; los datos IEC (tubo métrico,
  H07V) son aproximados — verifique con el fabricante.
- En IEC 60364 no hay un límite fijo de curvas/longitud: el perfil IEC usa una
  **referencia práctica** (3 × 90°, 15 m entre registros).
- La revisión no cubre capacidad de corriente, caída de tensión ni cálculo de
  cajas (NEC 314.16); son parte del diseño eléctrico.

---

## ❤️ Donaciones

SKP E-Plumb es **software libre** (GPL-3.0). Si te resulta útil y quieres apoyar
su desarrollo, puedes hacer una donación por PayPal — ¡gracias!

<p>
  <a href="https://www.paypal.com/donate/?business=juanesgtgt2%40gmail.com&no_recurring=0&item_name=Apoyo%20a%20SKP%20E-Plumb&currency_code=USD">
    <img src="https://img.shields.io/badge/Donar%20con-PayPal-0070BA?logo=paypal&logoColor=white&style=for-the-badge" alt="Donar con PayPal">
  </a>
</p>

- **PayPal:** [donar](https://www.paypal.com/donate/?business=juanesgtgt2%40gmail.com&no_recurring=0&item_name=Apoyo%20a%20SKP%20E-Plumb&currency_code=USD) · `juanesgtgt2@gmail.com`

---

## 📖 English (summary)

**SKP E-Plumb** is a SketchUp extension (2019+, tested for SketchUp 2026 on
macOS/Windows) to draw **electrical conduit** runs **on** walls, floors and
ceilings (exposed) or **inside** them (embedded) — tubes no longer cut through
surfaces, and bends over outside corners clear the edge. Boxes face out of the
surface they are placed on, with a live 3D preview and 90° rotation. It checks
runs against **NTC 2050 + RETIE**, **NEC** or **IEC 60364** (360° of bends
between pull points with optional automatic pull boxes, Chapter 9 conduit fill
with THHN/THW/H07V conductors, support spacing, minimum bend radius, conductor
colour codes) and produces a **Bill of Materials** with pipes per stock length,
couplings, elbows, terminations, supports, boxes, conductors and the product
standard of each item, plus a **code review** tab. Licensed under
**GPL-3.0-or-later**.

---

## 📜 Licencia

Copyright © 2026 AA-EION.

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo los
términos de la **Licencia Pública General GNU (GPL) versión 3** o posterior,
publicada por la Free Software Foundation. Se distribuye **SIN GARANTÍA
ALGUNA**. Consulta el archivo [`LICENSE`](LICENSE) o
<https://www.gnu.org/licenses/gpl-3.0.html>.
