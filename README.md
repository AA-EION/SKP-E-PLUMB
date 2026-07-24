# SKP E-Plumb — Modelador de canalizaciones eléctricas + BOM para SketchUp

[![Donar con PayPal](https://img.shields.io/badge/Donar-PayPal-0070BA?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=juanesgtgt2%40gmail.com&no_recurring=0&item_name=Apoyo%20a%20SKP%20E-Plumb&currency_code=USD)
[![Licencia: GPL-3.0](https://img.shields.io/badge/Licencia-GPL--3.0-blue)](LICENSE)

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
- Versión: **1.8.0**
- Formato de instalación: **`.rbz`**

---

## ✨ Características

- **Dibujo intuitivo**: marca el trazado con clics; la tubería, coplas,
  codos y terminaciones se generan solas.
- **Diámetro configurable** por medida comercial (1/2" … 4") con diámetro
  exterior real por tipo de canalización.
- **Inventario / tramo de stock**: define el largo máximo de tubo disponible
  (p. ej. **3 m**). El plugin:
  - **grafica cada tubo como una pieza independiente** de ≤ el largo de stock,
    para que veas dónde queda cada tubo;
  - coloca una **copla montada sobre cada empalme** (un tubo termina, empieza el
    siguiente y encima queda la copla); y
  - cuenta en el BOM **un tubo por pieza dibujada** (más los metros totales).
- **Montaje sobrepuesto**: opción para que el tubo quede **apoyado sobre** la
  pared/piso/techo (no medio enterrado), desplazándolo por el normal de la
  superficie donde se dibujó.
- **Caja automática (RETIE)**: opción para que **tras cada N curvas** (por
  defecto 2) la tubería **llegue a una caja**, se coloque la **terminación**
  (conector/contratuerca + bushing normal o de aterrizaje) y **continúe** al
  otro lado con su propia terminación — la caja **reemplaza** esa curva. La caja
  se **monta contra la superficie** donde se dibujó el punto (pared/piso/techo),
  con su cara ancha paralela a ella. Activable/desactivable en Ajustes.
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
- **Conexión a cajas (snap)**: al dibujar, si pasas el cursor sobre una caja del
  plugin, la tubería **se conecta** a ella (llega a la cara correcta con su
  terminación). Una caja puede recibir **varias tuberías**; un tubo que atraviesa
  la caja entra por una cara y **sale por la opuesta** (caja a cada lado de un
  muro).
- **Edición por anclas**: reabre cualquier tubería creada y **mueve, inserta o
  borra vértices, extiéndela y cambia curva↔codo por vértice**; la geometría y
  el BOM se **reconstruyen** al aplicar.
- **BOM en vivo** con exportación a **CSV** y **HTML**, agrupado por categoría,
  tipo y medida.
- Barra de herramientas, menú, íconos y **Diagnóstico** propios. Todo el
  modelado se hace dentro de una sola operación *undo-able*.

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

1. Descarga **`SKP-E-Plumb.rbz`** desde la
   [última Release](../../releases/latest). El `.rbz` se publica únicamente en
   las Releases (no se versiona dentro del repositorio).
2. En SketchUp: **Ventana → Administrador de extensiones → Instalar extensión…**
   (*Window → Extension Manager → Install Extension…*).
3. Selecciona el `.rbz` y confirma.
4. Aparecerá el menú **Extensiones → SKP E-Plumb** y su **barra de herramientas**.
   Si no ves algo, usa **Extensiones → SKP E-Plumb → Diagnóstico…** para
   comprobar la carga y abrir Ajustes.

> Compatible con SketchUp 2017 en adelante (usa `HtmlDialog`), probado para
> **SketchUp 2026** en macOS y Windows.

### Actualizaciones

El plugin puede **auto-actualizarse desde los Releases de GitHub** (macOS y
Windows):

- **Extensiones → SKP E-Plumb → Buscar actualizaciones…** consulta la última
  versión y, si hay una nueva, ofrece **descargar e instalar** el `.rbz`
  automáticamente (`Sketchup.install_from_archive`) o abrir la página.
- Un **aviso automático** (1×/día) revisa si hay novedades; se puede desactivar
  en *Ajustes → Actualizaciones*.

> La auto-actualización *gestionada por el Administrador de extensiones* de
> SketchUp requiere publicar en el **Extension Warehouse** (y firma de Trimble).
> Este mecanismo propio no la sustituye, pero cumple la misma función sin el
> Warehouse.

---

## 🚀 Uso rápido

1. Abre **Extensiones → SKP E-Plumb → Ajustes…** y define:
   - **Tipo** de canalización (EMT / IMC / GALV / PVC).
   - **Diámetro** comercial.
   - **Tramo en inventario (m)** — largo máximo por tubo.
   - **Radio de curvatura (mm)** — o pulsa *“usar mínimo NEC”*.
   - **Modo de curva**, **unión** (EMT), **terminación** y **caja activa**.
   - **Caja automática (RETIE)**: actívala para que, al dibujar, se coloque la
     caja activa tras cada N curvas.
2. Pulsa **✏️ Dibujar tubería** (o el ícono de la barra).
3. **Haz clic** para marcar cada punto del trazado. Puedes:
   - Escribir una **longitud exacta** en el cuadro de medidas (VCB) y Enter.
   - Pulsar **`Alt` / `Option`** para alternar entre **doblar tubo** y
     **codo prefabricado** *antes de marcar cada esquina*.
   - **Backspace** para deshacer el último punto.
4. **Doble clic** o **Enter** para construir el tramo. El BOM se actualiza.
5. Para **cajas**: en **Ajustes** elige la **Caja activa** (Plexo o Rawelt);
   luego pulsa **▧ Colocar caja** y **haz clic** donde la quieras. Se monta
   sobre la cara si haces clic en una (p. ej. una pared o un tablero), o sobre
   el plano del piso si haces clic en espacio vacío. Cada clic coloca otra
   caja; pulsa **Esc** para terminar.
6. Abre **📋 Ver BOM** y expórtalo a **CSV** o **HTML**.

### Editar una tubería existente (por anclas)

Pulsa **Editar tubería** y haz clic en una tubería creada con el plugin. Aparecen
las **anclas** de su trazado:

| Acción | Cómo |
|--------|------|
| Mover un vértice | **Arrastra** su ancla |
| Insertar un vértice | **Clic sobre un segmento** |
| Extender la tubería | **Clic en espacio vacío** (se agrega al extremo más cercano) |
| Borrar un vértice | Coloca el cursor sobre el ancla y pulsa **Retroceso/Supr** |
| Cambiar tipo de nodo (curva → codo → caja) | Cursor sobre el ancla + **Alt / Option** (azul=curva, verde=codo, naranja=caja) |
| Aplicar cambios | **Enter** (reconstruye geometría y BOM) |
| Cancelar | **Esc** |

---

## 🧮 Cómo se calcula el BOM

Cada pieza modelada lleva metadatos (diccionario de atributos `SKP_E_PLUMB`).
El BOM se **deriva del modelo**, así que si borras una tubería o un codo, el
conteo se actualiza al regenerarlo.

- **Tubería** — dos modos de conteo seleccionables en el diálogo del BOM:
  - **Por tramos cortados**: cada pieza dibujada = 1 tubo.
  - **Optimizado (recorrido total)**: suma todos los metros del mismo
    tipo/medida en el modelo y calcula tubos = ⌈total / tramo⌉ (reutiliza
    retazos). Siempre se muestran los metros totales.
- **Coplas**: una **montada sobre cada empalme** entre tubos consecutivos, más
  dos por cada codo prefabricado.
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
  edit_tool.rb            # Edición por anclas de tuberías existentes
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
- La edición por anclas reconstruye la tubería completa al aplicar (no edita
  pieza por pieza).
- Próximo: numeración de circuitos, longitud de conductores, cédulas por caja,
  reporte por planta.

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

**SKP E-Plumb** is a SketchUp 2026 extension (macOS/Windows) to draw
**electrical conduit** runs and generate a **Bill of Materials** that respects
your **stock pipe length**. It supports **PVC, EMT, IMC and Galvanized/RMC**
with correct joints (set-screw/compression for EMT, threaded for IMC/RMC,
solvent-weld for PVC), **field bends vs. factory elbows** (toggle with
`Alt`/`Option` while drawing), configurable **bend radius** (NEC minimums),
**insulated and grounding bushings**, and **Plexo / Rawelt boxes**. Existing
runs are **editable by anchors** (drag/insert/delete vertices, extend, toggle
bend/elbow per vertex, then rebuild). Install the `.rbz` via *Extension
Manager*. Export the BOM to CSV/HTML. Licensed under **GPL-3.0-or-later**.

---

## 📜 Licencia

Copyright © 2026 AA-EION.

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo los
términos de la **Licencia Pública General GNU (GPL) versión 3** o posterior,
publicada por la Free Software Foundation. Se distribuye **SIN GARANTÍA
ALGUNA**. Consulta el archivo [`LICENSE`](LICENSE) o
<https://www.gnu.org/licenses/gpl-3.0.html>.
