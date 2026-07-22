# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # UIDialogs
  # ---------------------------------------------------------------------------
  # HtmlDialog based UI. Two dialogs:
  #   * Settings — pick conduit type, diameter, stock length, bend radius, bend
  #     mode, connection method, termination and the active box.
  #   * BOM — a live table with CSV / HTML export.
  # HtmlDialog is available on SketchUp 2017+ and is cross-platform (macOS and
  # Windows), which is what SketchUp 2026 uses.
  # ===========================================================================
  module UIDialogs
    @settings_dlg = nil
    @bom_dlg = nil

    module_function

    # ---- Settings dialog --------------------------------------------------

    def show_settings
      if @settings_dlg&.visible?
        @settings_dlg.bring_to_front
        return
      end

      @settings_dlg = UI::HtmlDialog.new(
        dialog_title: 'SKP E-Plumb — Ajustes',
        preferences_key: 'com.aaeion.skpeplumb.settings',
        scrollable: true, resizable: true,
        width: 380, height: 640, min_width: 340, min_height: 420,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      # Register callbacks BEFORE loading the page so the sketchup.* bindings
      # exist as soon as the HTML runs.
      register_settings_callbacks(@settings_dlg)
      @settings_dlg.set_html(settings_html)
      @settings_dlg.show
      @settings_dlg.center if @settings_dlg.respond_to?(:center)
    rescue StandardError => e
      report_error(e, 'Ajustes')
    end

    def register_settings_callbacks(dlg)
      dlg.add_action_callback('set_value') do |_ctx, key, value|
        case key
        when 'size'
          Settings.apply_size!(value)
          dlg.execute_script("document.getElementById('bend_radius_mm').value=" \
                             "'#{Settings.bend_radius_mm.round(1)}';")
          dlg.execute_script("flash('Guardado');")
        when 'type'
          Settings.set('type', value)
          # Re-render so diameters/OD and connection options follow the type.
          dlg.set_html(settings_html)
        else
          Settings.set(key, coerce(key, value))
          dlg.execute_script("flash('Guardado');")
        end
        nil
      end

      dlg.add_action_callback('apply_nec') do |_ctx|
        r = Catalog.min_bend_radius_mm(Settings.size)
        Settings.set('bend_radius_mm', r)
        dlg.execute_script("document.getElementById('bend_radius_mm').value='#{r.round(1)}';")
        dlg.execute_script("flash('Radio mínimo NEC aplicado');")
        nil
      end

      dlg.add_action_callback('draw_conduit') do |_ctx|
        Sketchup.active_model.select_tool(ConduitTool.new)
        nil
      end

      dlg.add_action_callback('place_box') do |_ctx|
        Sketchup.active_model.select_tool(BoxTool.new)
        nil
      end

      dlg.add_action_callback('show_bom') do |_ctx|
        show_bom
        nil
      end
    end

    def coerce(key, value)
      case key
      when 'stock_m', 'bend_radius_mm' then value.to_f
      when 'segments', 'auto_box_every' then value.to_i
      when 'auto_box' then value.to_s == 'true'
      else value
      end
    end

    def settings_html
      s = Settings
      type_opts = Catalog::TYPE_KEYS.map do |k|
        sel = k == s.type ? 'selected' : ''
        "<option value='#{k}' #{sel}>#{Bom.h(Catalog::TYPES[k][:label])}</option>"
      end.join

      size_opts = Catalog::TRADE_SIZES.map do |sz|
        sel = sz == s.size ? 'selected' : ''
        od = Catalog.od_mm(s.type, sz)
        "<option value='#{sz}' #{sel}>#{sz}\" · OD #{od} mm · Ø#{Catalog::METRIC_DESIGNATOR[sz]}</option>"
      end.join

      box_opts = Catalog::BOX_KEYS.map do |k|
        sel = k == s.box_key ? 'selected' : ''
        "<option value='#{k}' #{sel}>#{Bom.h(Catalog::BOXES[k][:label])}</option>"
      end.join

      term_opts = { 'none' => 'Sin terminación (continúa)',
                    'std' => 'Conector/locknut + bushing aislante',
                    'gnd' => 'Conector/locknut + bushing de aterrizaje' }
                  .map do |k, v|
        sel = k == s.get('termination') ? 'selected' : ''
        "<option value='#{k}' #{sel}>#{v}</option>"
      end.join

      conn_opts = { 'setscrew' => 'Set-screw (tornillo)',
                    'compression' => 'Compresión' }.map do |k, v|
        sel = k == s.get('connection') ? 'selected' : ''
        "<option value='#{k}' #{sel}>#{v}</option>"
      end.join

      field_ck = s.field_bend? ? 'checked' : ''
      premade_ck = s.field_bend? ? '' : 'checked'
      auto_ck = s.auto_box? ? 'checked' : ''

      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root{--b:#2b6cb0;--bg:#f6f7f9;--line:#d6d9df;--tx:#1b1e24}
          *{box-sizing:border-box}
          body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:0;color:var(--tx);background:var(--bg);font-size:13px}
          header{background:var(--b);color:#fff;padding:12px 16px}
          header h1{margin:0;font-size:15px}
          header p{margin:2px 0 0;font-size:11px;opacity:.9}
          .wrap{padding:14px 16px}
          label{display:block;font-weight:600;margin:12px 0 4px}
          select,input[type=number]{width:100%;padding:7px 8px;border:1px solid var(--line);border-radius:6px;background:#fff;font-size:13px}
          .hint{color:#777;font-size:11px;margin-top:3px}
          .row{display:flex;gap:8px}.row>div{flex:1}
          .modes{display:flex;gap:8px;margin-top:4px}
          .modes label{flex:1;font-weight:500;border:1px solid var(--line);border-radius:6px;padding:8px;cursor:pointer;background:#fff;margin:0}
          .modes input{margin-right:6px}
          .btns{margin-top:16px;display:flex;flex-direction:column;gap:8px}
          button{padding:10px;border:0;border-radius:6px;font-size:13px;font-weight:600;cursor:pointer}
          .primary{background:var(--b);color:#fff}
          .ghost{background:#e8ebf0;color:#222}
          #flash{position:fixed;bottom:10px;left:16px;right:16px;background:#1f9d55;color:#fff;padding:8px;border-radius:6px;text-align:center;opacity:0;transition:.3s;font-size:12px}
          hr{border:0;border-top:1px solid var(--line);margin:16px 0}
        </style></head><body>
        <header><h1>SKP E-Plumb</h1><p>Canalizaciones eléctricas &amp; BOM</p></header>
        <div class="wrap">
          <label>Tipo de canalización</label>
          <select id="type" onchange="setV('type',this.value)">#{type_opts}</select>

          <label>Diámetro (medida comercial)</label>
          <select id="size" onchange="setV('size',this.value)">#{size_opts}</select>
          <div class="hint">Diámetro exterior mostrado por tipo/medida.</div>

          <div class="row">
            <div>
              <label>Tramo en inventario (m)</label>
              <input type="number" id="stock_m" min="0.5" step="0.1" value="#{s.stock_m}"
                     onchange="setV('stock_m',this.value)">
              <div class="hint">Largo máx. por tubo. Define coplas y # de tubos.</div>
            </div>
            <div>
              <label>Radio de curvatura (mm)</label>
              <input type="number" id="bend_radius_mm" min="10" step="1" value="#{s.bend_radius_mm.round(1)}"
                     onchange="setV('bend_radius_mm',this.value)">
              <div class="hint"><a href="#" onclick="nec();return false">Usar mínimo NEC</a></div>
            </div>
          </div>

          <label>Modo de curva (Alt / Option cambia en vivo)</label>
          <div class="modes">
            <label><input type="radio" name="bm" #{field_ck}
              onclick="setV('bend_mode','field')">Doblar tubo</label>
            <label><input type="radio" name="bm" #{premade_ck}
              onclick="setV('bend_mode','premade')">Codo prefabricado</label>
          </div>

          <label>Unión (solo EMT)</label>
          <select id="connection" onchange="setV('connection',this.value)">#{conn_opts}</select>
          <div class="hint">IMC/Galvanizado: roscado · PVC: cementado (automático).</div>

          <label>Terminación a caja/tablero</label>
          <select id="termination" onchange="setV('termination',this.value)">#{term_opts}</select>

          <div class="row">
            <div>
              <label>Facetas del tubo</label>
              <input type="number" id="segments" min="8" max="64" step="1" value="#{s.segments}"
                     onchange="setV('segments',this.value)">
            </div>
            <div>
              <label>Caja activa</label>
              <select id="box_key" onchange="setV('box_key',this.value)">#{box_opts}</select>
            </div>
          </div>

          <label>Caja automática (RETIE)</label>
          <div class="modes" style="align-items:center">
            <label style="flex:0 0 auto"><input type="checkbox" id="auto_box" #{auto_ck}
              onclick="setV('auto_box', this.checked ? 'true' : 'false')"> Activar</label>
            <span style="flex:1">cada
              <input type="number" id="auto_box_every" min="1" max="10" step="1"
                     value="#{s.auto_box_every}" style="width:56px"
                     onchange="setV('auto_box_every',this.value)"> curva(s) coloca la <b>caja activa</b></span>
          </div>
          <div class="hint">Inserta la caja seleccionada arriba tras cada N curvas del trazado.</div>

          <hr>
          <div class="btns">
            <button class="primary" onclick="sketchup.draw_conduit()">✏️ Dibujar tubería</button>
            <button class="ghost" onclick="sketchup.place_box()">▧ Colocar caja</button>
            <button class="ghost" onclick="sketchup.show_bom()">📋 Ver BOM</button>
          </div>
        </div>
        <div id="flash"></div>
        <script>
          function setV(k,v){ sketchup.set_value(k,v); }
          function nec(){ sketchup.apply_nec(); }
          function flash(msg){ var f=document.getElementById('flash'); f.textContent=msg;
            f.style.opacity=1; clearTimeout(window._ft);
            window._ft=setTimeout(function(){f.style.opacity=0;},1200); }
        </script>
        </body></html>
      HTML
    end

    # NOTE: reload() re-renders with the freshly saved type so diameters and
    # defaults follow the type. It calls back into settings_html via set_html.
    def refresh_settings
      @settings_dlg&.set_html(settings_html) if @settings_dlg&.visible?
    end

    # ---- BOM dialog -------------------------------------------------------

    def show_bom
      data = Bom.aggregate

      if @bom_dlg&.visible?
        @bom_dlg.execute_script("document.getElementById('tbl').innerHTML=" \
                                "#{js_string(Bom.table_html(data))};")
        @bom_dlg.bring_to_front
        return
      end

      @bom_dlg = UI::HtmlDialog.new(
        dialog_title: 'SKP E-Plumb — BOM',
        preferences_key: 'com.aaeion.skpeplumb.bom',
        scrollable: true, resizable: true,
        width: 720, height: 540, min_width: 460, min_height: 300,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      register_bom_callbacks(@bom_dlg)
      @bom_dlg.set_html(bom_dialog_html(data))
      @bom_dlg.show
      @bom_dlg.center if @bom_dlg.respond_to?(:center)
    rescue StandardError => e
      report_error(e, 'BOM')
    end

    # Show any failure in a message box so silent errors become reportable.
    def report_error(err, context)
      trace = (err.backtrace || [])[0, 6].join("\n")
      UI.messagebox("SKP E-Plumb — error en #{context}:\n\n#{err.class}: " \
                    "#{err.message}\n\n#{trace}")
    end

    def register_bom_callbacks(dlg)
      dlg.add_action_callback('refresh') do |_ctx|
        data = Bom.aggregate
        dlg.execute_script("document.getElementById('tbl').innerHTML=" \
                           "#{js_string(Bom.table_html(data))};")
        nil
      end

      dlg.add_action_callback('export_csv') do |_ctx|
        export_bom(:csv)
        nil
      end

      dlg.add_action_callback('export_html') do |_ctx|
        export_bom(:html)
        nil
      end
    end

    def export_bom(fmt)
      data = Bom.aggregate
      default = fmt == :csv ? 'BOM_SKP_E_Plumb.csv' : 'BOM_SKP_E_Plumb.html'
      path = UI.savepanel('Guardar BOM', dir_hint, default)
      return unless path

      content = fmt == :csv ? Bom.to_csv(data) : Bom.to_html(data)
      File.open(path, 'w:UTF-8') { |f| f.write(content) }
      UI.messagebox("BOM exportado:\n#{path}")
    rescue StandardError => e
      UI.messagebox("No se pudo exportar: #{e.message}")
    end

    def dir_hint
      model_path = Sketchup.active_model.path
      model_path.empty? ? nil : File.dirname(model_path)
    end

    def bom_dialog_html(data)
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <style>
          body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:0;color:#1b1e24;background:#fff;font-size:13px}
          .bar{position:sticky;top:0;background:#2b6cb0;color:#fff;padding:10px 16px;display:flex;gap:8px;align-items:center}
          .bar h1{font-size:15px;margin:0;flex:1}
          .bar button{background:#fff;color:#2b6cb0;border:0;border-radius:6px;padding:7px 12px;font-weight:600;cursor:pointer}
          .content{padding:16px}
          table{border-collapse:collapse;width:100%;font-size:13px}
          th,td{border:1px solid #d4d7dd;padding:6px 8px;text-align:left}
          th{background:#eef2f7}
          tr:nth-child(even){background:#f7f9fb}
          td.c{text-align:center}td.n{text-align:right;font-variant-numeric:tabular-nums}
          .empty{color:#889;font-style:italic}
        </style></head><body>
        <div class="bar">
          <h1>Lista de materiales (BOM)</h1>
          <button onclick="sketchup.refresh()">↻ Actualizar</button>
          <button onclick="sketchup.export_csv()">CSV</button>
          <button onclick="sketchup.export_html()">HTML</button>
        </div>
        <div class="content"><div id="tbl">#{Bom.table_html(data)}</div></div>
        </body></html>
      HTML
    end

    # ---- helpers ----------------------------------------------------------

    # Encode a Ruby string as a safe JS string literal for execute_script.
    def js_string(str)
      str.to_json
    rescue StandardError
      escaped = str.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")
                   .gsub("\n", '\\n').gsub("\r", '')
      "'#{escaped}'"
    end
  end
end
