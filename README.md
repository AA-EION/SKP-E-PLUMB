# SKP E-Plumb — Modelador de canalizaciones eléctricas + BOM para SketchUp

**SKP E-Plumb** es una extensión para **SketchUp 2026** (compatible con
**macOS** y **Windows**) que permite dibujar **canalizaciones / tuberías
eléctricas** de forma rápida e intuitiva y generar automáticamente una
**lista de materiales (BOM)** que respeta el **tramo comercial de tubería**
que tienes en inventario.

Soporta **PVC eléctrico, EMT, IMC y Galvanizado (RMC)** representando
correctamente cada tipo de unión y accesorio: coplas, codos, curvas hechas en
obra, bushings (aislantes y de aterrizaje), contratuercas y cajas
(**Plexo** y **Rawelt**).

> ⚡ *Herramienta de modelado y estimación. No sustituye el cálculo ni la
> revisión de un profesional ni el cumplimiento del código eléctrico local
> (NEC / NOM / RETIE, etc.).*

- Licencia: **GPL-3.0-or-later**
- Versión: **1.0.0**
- Formato de instalación: **`.rbz`**

---

## ✨ Características

- **Dibujo intuitivo**: marca el trazado con clics; la tubería, coplas,
  codos y terminaciones se generan solas.
- **Diámetro configurable** por medida comercial (1/2" … 4") con diámetro
  exterior real por tipo de canalización.
- **Inventario / tramo de stock**: define el largo máximo de tubo disponible
  (p. ej. **3 m**). El plugin:
  - coloca una **copla en cada empalme** cuando un tramo recto excede el largo
    de stock, y
  - calcula en el BOM **cuántos tubos** hay que comprar = `⌈metros / tramo⌉`.
- **Curvas: dos modos** — se alternan **en vivo con `Alt` / `Option`**
  (o `Ctrl` en Windows) mientras dibujas:
  1. **Doblar tubo (curva de campo)** — la curva es parte del mismo tubo y su
     longitud se suma a los metros de tubería. *No* genera accesorio (es la
     razón real por la que se dobla en obra).
  2. **Codo prefabricado** — inserta un **codo 45°/90°** como **ítem
     independiente** del BOM y lo une con coplas.
- **Radio de curvatura configurable**, con botón *“usar mínimo NEC”* que
  aplica el radio mínimo del [NEC Cap. 9, Tabla 2] según la medida.
- **Uniones correctas por tipo**:
  - **EMT** → coplas/conectores **set-screw o a compresión** (no roscados).
  - **IMC / Galvanizado** → **roscados** (copla roscada, y en cajas
    **contratuerca + bushing**).
  - **PVC** → **cementado** (copla de pegar, adaptador terminal a cajas).
- **Terminaciones a cajas/tableros** con los accesorios correctos, incluyendo
  **bushing normal (aislante)** o **bushing de aterrizaje (grounding)**.
- **Cajas**:
  - **Plexo** (cajas plásticas IP55 para intemperie / PVC).
  - **Rawelt** (condulets tipo **C, LB, LL, LR, T, X** y cajas **FS / FD**).
- **BOM en vivo** con exportación a **CSV** y **HTML**, agrupado por categoría,
  tipo y medida.
- Barra de herramientas, menú e íconos propios. Todo el modelado se hace dentro
  de una sola operación *undo-able*.

---

## 🧱 Tipos de canalización soportados

| Tipo | Nombre | Unión entre tubos | Curvas | Terminación a caja |
|------|--------|-------------------|--------|--------------------|
| **EMT** | Tubo conduit pared delgada | Set-screw / compresión (no roscado) | Doblado en obra o codo | Conector set-screw/compresión (+ bushing opcional) |
| **IMC** | Pared intermedia | **Roscado** | Doblado en obra o codo | **Contratuerca + bushing** |
| **GALV / RMC** | Galvanizado pared gruesa | **Roscado** | Doblado en obra o codo | **Contratuerca + bushing** |
| **PVC** | PVC eléctrico Sch-40 | **Cementado (pegar)** | Codo prefabricado | Adaptador terminal + contratuerca |

Diámetros comerciales: `1/2"`, `3/4"`, `1"`, `1-1/4"`, `1-1/2"`, `2"`,
`2-1/2"`, `3"`, `3-1/2"`, `4"`.

---

## 📦 Instalación

1. Descarga el archivo **`SKP-E-Plumb.rbz`** (de
   [Releases](../../releases) o de la carpeta [`dist/`](dist/)).
2. En SketchUp: **Ventana → Administrador de extensiones → Instalar extensión…**
   (*Window → Extension Manager → Install Extension…*).
3. Selecciona el `.rbz` y confirma.
4. Aparecerá el menú **Extensiones → SKP E-Plumb** y su **barra de herramientas**.

> Compatible con SketchUp 2017 en adelante (usa `HtmlDialog`), probado para
> **SketchUp 2026** en macOS y Windows.

---

## 🚀 Uso rápido

1. Abre **Extensiones → SKP E-Plumb → Ajustes…** y define:
   - **Tipo** de canalización (EMT / IMC / GALV / PVC).
   - **Diámetro** comercial.
   - **Tramo en inventario (m)** — largo máximo por tubo.
   - **Radio de curvatura (mm)** — o pulsa *“usar mínimo NEC”*.
   - **Modo de curva**, **unión** (EMT), **terminación** y **caja activa**.
2. Pulsa **✏️ Dibujar tubería** (o el ícono de la barra).
3. **Haz clic** para marcar cada punto del trazado. Puedes:
   - Escribir una **longitud exacta** en el cuadro de medidas (VCB) y Enter.
   - Pulsar **`Alt` / `Option`** para alternar entre **doblar tubo** y
     **codo prefabricado** *antes de marcar cada esquina*.
   - **Backspace** para deshacer el último punto.
4. **Doble clic** o **Enter** para construir el tramo. El BOM se actualiza.
5. Para **cajas**: pulsa **▧ Colocar caja** y haz clic donde la quieras (se
   monta sobre la cara si hay una).
6. Abre **📋 Ver BOM** y expórtalo a **CSV** o **HTML**.

---

## 🧮 Cómo se calcula el BOM

Cada pieza modelada lleva metadatos (diccionario de atributos `SKP_E_PLUMB`).
El BOM se **deriva del modelo**, así que si borras una tubería o un codo, el
conteo se actualiza al regenerarlo.

- **Tubería**: se suman los **metros** por (tipo, medida) y se calcula
  `tubos = ⌈metros / tramo_de_stock⌉`. El detalle muestra los metros totales y
  el tramo usado.
- **Coplas**: una por cada empalme obligado por el largo de stock en tramos
  rectos, más dos por cada codo prefabricado.
- **Codos 45°/90°**: uno por cada curva hecha en modo *prefabricado*.
- **Curvas de campo**: no generan accesorio; su arco se **suma a los metros**
  de tubería.
- **Terminaciones**: conector/contratuerca + bushing (aislante o de
  aterrizaje) según el tipo y la opción elegida.
- **Cajas**: una por cada caja colocada.

---

## 🛠️ Compilar desde el código

Requisitos: `ruby` y `zip`.

```bash
# Genera los íconos PNG (opcional, ya vienen incluidos)
ruby tools/make_icons.rb

# Empaqueta el .rbz en dist/
./tools/build_rbz.sh

# Ejecuta las pruebas de lógica (catálogo + BOM)
ruby tools/test_logic.rb
```

Estructura del proyecto:

```
skp_e_plumb.rb            # Registro de la extensión (raíz del .rbz)
skp_e_plumb/
  main.rb                 # Carga módulos, menús, barra de herramientas
  catalog.rb              # Tipos, diámetros, radios NEC, accesorios, cajas
  geom_util.rb            # Primitivas geométricas (tubos, arcos, cajas)
  builder.rb              # Convierte el trazado en geometría + BOM
  bom.rb                  # Motor de BOM y exportación CSV/HTML
  settings.rb             # Preferencias persistentes
  conduit_tool.rb         # Herramienta interactiva de tubería
  box_tool.rb             # Herramienta de cajas
  ui_dialogs.rb           # Diálogos HtmlDialog (Ajustes y BOM)
  resources/icons/*.png   # Íconos de la barra de herramientas
tools/                    # Scripts de build, íconos y pruebas
```

---

## ⚠️ Limitaciones / hoja de ruta

- La geometría es **representativa** (ODs reales por tipo/medida, arcos
  segmentados). No modela roscas ni el interior hueco del tubo.
- El conteo de tubos asume reaprovechamiento de retazos (estimación optimista);
  el BOM muestra también los metros para que el estimador ajuste.
- Próximo: numeración de circuitos, longitud de conductores, cédulas por caja,
  reporte por planta.

---

## 📖 English (summary)

**SKP E-Plumb** is a SketchUp 2026 extension (macOS/Windows) to draw
**electrical conduit** runs and generate a **Bill of Materials** that respects
your **stock pipe length**. It supports **PVC, EMT, IMC and Galvanized/RMC**
with correct joints (set-screw/compression for EMT, threaded for IMC/RMC,
solvent-weld for PVC), **field bends vs. factory elbows** (toggle with
`Alt`/`Option` while drawing), configurable **bend radius** (NEC minimums),
**insulated and grounding bushings**, and **Plexo / Rawelt boxes**. Install the
`.rbz` via *Extension Manager*. Export the BOM to CSV/HTML. Licensed under
**GPL-3.0-or-later**.

---

## 📜 Licencia

Copyright © 2026 AA-EION.

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo los
términos de la **Licencia Pública General GNU (GPL) versión 3** o posterior,
publicada por la Free Software Foundation. Se distribuye **SIN GARANTÍA
ALGUNA**. Consulta el archivo [`LICENSE`](LICENSE) o
<https://www.gnu.org/licenses/gpl-3.0.html>.
