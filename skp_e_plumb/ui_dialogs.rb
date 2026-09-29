# frozen_string_literal: true

begin
  require 'json'
rescue LoadError
  nil
end

module SkpEPlumb
  # ===========================================================================
  # UIDialogs
  # ---------------------------------------------------------------------------
  # HtmlDialog based UI:
  #   * Panel (settings) — one clean, sectioned panel: code profile, raceway,
  #     bends, boxes, conductors (live fill check) and advanced options. The
  #     page is rendered by JS from a state object that Ruby pushes after
  #     every change, so dependent options (sizes, EMT joints, wire gauges…)
  #     always stay consistent without reloading the page.
  #   * Materials (BOM) — live table + code review, CSV / HTML export.
  #   * About / What's new.
  # ===========================================================================
  module UIDialogs
    @settings_dlg = nil
    @bom_dlg = nil
    @about_dlg = nil
    @whatsnew_dlg = nil

    module_function

    # ---- Panel (settings) ---------------------------------------------------

    def show_settings
      if @settings_dlg&.visible?
        @settings_dlg.bring_to_front
        return
      end

      @settings_dlg = UI::HtmlDialog.new(
        dialog_title: 'SKP E-Plumb',
        preferences_key: 'com.aaeion.skpeplumb.panel',
        scrollable: true, resizable: true,
        width: 390, height: 760, min_width: 340, min_height: 420,
        style: UI::HtmlDialog::STYLE_UTILITY
      )
      register_settings_callbacks(@settings_dlg)
      @settings_dlg.set_html(settings_html)
      @settings_dlg.show
    rescue StandardError => e
      report_error(e, 'Panel')
    end

    def refresh_settings
      push_state(@settings_dlg) if @settings_dlg&.visible?
    rescue StandardError
      nil
    end

    def push_state(dlg, toast = nil)
      js = "render(#{safe_json(settings_state)});"
      js += "flash(#{js_string(toast)});" if toast
      dlg.execute_script(js)
    end

    def register_settings_callbacks(dlg)
      dlg.add_action_callback('set_value') do |_ctx, key, value|
        begin
          apply_setting(key.to_s, value)
          push_state(dlg, 'Guardado')
        rescue StandardError => e
          report_error(e, 'Ajustes')
        end
        nil
      end
      dlg.add_action_callback('min_radius') do |_ctx|
        Settings.set('bend_radius_mm', Catalog.min_bend_radius_mm(Settings.type, Settings.size))
        push_state(dlg, 'Radio mínimo aplicado')
        nil
      end
      dlg.add_action_callback('suggest_size') do |_ctx|
        sug = Codes.min_size(Settings.type, Codes.conductors(Settings.wiring_spec))
        if sug
          Settings.apply_size!(sug)
          push_state(dlg, "Diámetro #{Catalog.size_text(Settings.type, sug)}")
        else
          push_state(dlg, 'Ningún diámetro de este tipo alcanza')
        end
        nil
      end
      dlg.add_action_callback('tool') do |_ctx, name|
        Menus.safe(name.to_s) { Menus.activate_tool(name.to_s) }
        nil
      end
      dlg.add_action_callback('show_bom') do |_ctx|
        show_bom
        nil
      end
    end

    def apply_setting(key, value)
      case key
      when 'profile' then Settings.apply_profile!(value.to_s)
      when 'type' then Settings.apply_type!(value.to_s)
      when 'size' then Settings.apply_size!(value.to_s)
      when 'insulation'
        Settings.set('insulation', value.to_s)
        Settings.sanitize!
        Settings.set('wire_size', Settings.get('wire_size'))
        Settings.set('ground_size', Settings.get('ground_size'))
      else
        return unless Settings::DEFAULTS.key?(key)

        Settings.set(key, value)
      end
    end

    # Everything the panel needs to render itself.
    def settings_state
      s = Settings
      type = s.type
      prof = Codes.profile(s.profile)
      conds = Codes.conductors(s.wiring_spec)
      fill = Codes.fill(type, s.size, conds)
      sug = conds.empty? ? nil : Codes.min_size(type, conds)
      ins = Codes.insulation(s.get('insulation'))
      wire_sizes = Codes.sizes_for_units(ins[:units])
      art = Codes::ARTICLE[type]
      spacing = Codes.strap_spacing_m(s.profile, type, s.size)
      min_r = Catalog.min_bend_radius_mm(type, s.size)

      {
        v: s.state.merge('surface' => s.surface?),
        version: SkpEPlumb::VERSION,
        profiles: Codes::PROFILE_KEYS.map { |k| [k, Codes::PROFILES[k][:label]] },
        types: Catalog::TYPE_KEYS.map { |k| [k, Catalog::TYPES[k][:label]] },
        sizes: Catalog.sizes_for(type).map do |sz|
          [sz, "#{Catalog.size_text(type, sz)} · Ø ext. #{Catalog.od_mm(type, sz)} mm"]
        end,
        boxes: Catalog::BOX_KEYS.group_by { |k| Catalog::BOXES[k][:family] }.map do |fam, keys|
          [fam, keys.map { |k| [k, Catalog::BOXES[k][:label]] }]
        end,
        circuits: Codes::CIRCUITS.map { |k, v| [k, v[:label]] },
        systems: Codes::SYSTEMS.map { |k, v| [k, v[:label]] },
        insulations: Codes::INSULATION.map { |k, v| [k, v[:label]] },
        wire_sizes: wire_sizes.map { |w| [w, Codes.wire_label(w, s.get('insulation'))] },
        info: {
          is_emt: type == 'EMT',
          std: Catalog.type_info(type)[:std],
          min_radius: min_r.round,
          radius_ref: Catalog.metric?(type) ? 'recomendado 4×Ø' : 'Cap. 9 Tabla 2',
          code_summary: code_summary(prof, art, spacing),
          conds: conds.map { |c| { role: c[:role], color: c[:color], label: Codes.wire_label(c[:size], c[:ins]) } },
          fill: fill, suggest: sug && sug != s.size ? [sug, Catalog.size_text(type, sug)] : nil,
          fill_ref: prof[:code] == 'IEC 60364' ? 'referencia 40 %' : "#{prof[:code]} Cap. 9 Tabla 1"
        }
      }
    end

    def code_summary(prof, art, spacing)
      bends = if prof[:code] == 'IEC 60364'
                "Referencia práctica: ≤ #{prof[:max_bend_deg]}° de curvas y ≤ #{prof[:max_len_m]} m entre registros."
              else
                "Máx. #{prof[:max_bend_deg]}° de curvas entre cajas#{art ? " (#{art}.26)" : ''}."
              end
      supports = "Soportes cada ≤ #{spacing.round(2).to_s.sub(/\.0\z/, '')} m y a ≤ 0.9 m de cada caja" \
                 "#{art ? " (#{art}.30)" : ''}."
      colors = { retie: 'Colores de conductores según RETIE.', nec: 'Colores de conductores según NEC 200.6 / 250.119.',
                 iec: 'Colores de conductores según IEC 60445.' }[prof[:colors]]
      "#{bends} #{supports} #{colors}"
    end

    def settings_html
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root{--b:#1f5f99;--b2:#e8f0f8;--bg:#f3f5f8;--card:#fff;--line:#dde2e8;--tx:#1b1e24;--mut:#6b7380;--ok:#1a7f37;--bad:#b42318;--warn:#9a6700}
          *{box-sizing:border-box}
          body{font-family:"Segoe UI",-apple-system,Helvetica,Arial,sans-serif;margin:0;color:var(--tx);background:var(--bg);font-size:13px}
          header{background:var(--b);color:#fff;padding:12px 14px 10px;position:sticky;top:0;z-index:5}
          header h1{margin:0;font-size:15px;font-weight:600}
          header small{opacity:.8;font-size:11px}
          .acts{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-top:10px}
          .acts button{background:rgba(255,255,255,.14);color:#fff;border:1px solid rgba(255,255,255,.25);border-radius:7px;padding:7px 2px;font-size:12px;cursor:pointer;line-height:1.2}
          .acts button:hover{background:rgba(255,255,255,.26)}
          .acts b{display:block;font-size:16px}
          main{padding:10px}
          .card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:10px}
          .card h2{font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:var(--b);margin:0 0 8px}
          label.f{display:block;font-weight:600;margin:9px 0 4px;font-size:12px}
          select,input[type=number]{width:100%;padding:6px 8px;border:1px solid var(--line);border-radius:6px;background:#fff;font-size:13px;color:var(--tx)}
          .row{display:flex;gap:8px}.row>div{flex:1;min-width:0}
          .seg{display:flex;border:1px solid var(--line);border-radius:7px;overflow:hidden}
          .seg button{flex:1;border:0;background:#fff;padding:7px 4px;font-size:12px;cursor:pointer;color:var(--tx)}
          .seg button+button{border-left:1px solid var(--line)}
          .seg button.on{background:var(--b);color:#fff;font-weight:600}
          .hint{color:var(--mut);font-size:11px;margin-top:4px;line-height:1.35}
          .hint a{color:var(--b);cursor:pointer;text-decoration:underline}
          .sw{display:flex;align-items:center;gap:8px;margin:9px 0 2px;cursor:pointer;font-weight:600;font-size:12px}
          .sw input{width:16px;height:16px;margin:0}
          .inl{display:inline-block;width:64px;padding:3px 6px}
          .meter{height:8px;background:#e9edf2;border-radius:5px;overflow:hidden;margin-top:6px;position:relative}
          .meter i{display:block;height:100%;background:var(--ok)}
          .meter i.bad{background:var(--bad)}
          .meter s{position:absolute;top:-2px;bottom:-2px;width:2px;background:#333}
          .fill{display:flex;justify-content:space-between;font-size:12px;margin-top:8px}
          .fill b.ok{color:var(--ok)}.fill b.bad{color:var(--bad)}
          .chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:6px}
          .chip{display:inline-flex;align-items:center;gap:4px;border:1px solid var(--line);border-radius:12px;padding:2px 7px 2px 3px;font-size:11px;background:#fafbfc}
          .dot{width:12px;height:12px;border-radius:50%;border:1px solid rgba(0,0,0,.25)}
          .btn{margin-top:8px;width:100%;padding:7px;border:1px solid var(--b);color:var(--b);background:var(--b2);border-radius:7px;font-weight:600;cursor:pointer}
          details.card summary{cursor:pointer;font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:var(--b);font-weight:600;list-style:none}
          details.card summary::before{content:"▸ "}details[open].card summary::before{content:"▾ "}
          .sum{background:var(--b2);border-radius:7px;padding:7px 9px;color:#23405e;font-size:11.5px;line-height:1.4;margin-top:8px}
          #flash{position:fixed;bottom:10px;left:50%;transform:translateX(-50%);background:#1b1e24;color:#fff;padding:6px 14px;border-radius:14px;opacity:0;transition:.25s;font-size:12px;pointer-events:none}
        </style></head><body>
        <header>
          <h1>SKP E-Plumb <small id="ver"></small></h1>
          <div class="acts">
            <button onclick="sketchup.tool('draw')" title="Dibujar una tubería"><b>✏️</b>Tubería</button>
            <button onclick="sketchup.tool('box')" title="Colocar la caja activa"><b>▣</b>Caja</button>
            <button onclick="sketchup.tool('edit')" title="Editar una tubería existente"><b>✎</b>Editar</button>
            <button onclick="sketchup.show_bom()" title="Lista de materiales y revisión normativa"><b>☰</b>Materiales</button>
          </div>
        </header>
        <main id="app"></main>
        <div id="flash"></div>
        <script>
          var S = #{safe_json(settings_state)};
          var COLORS = {"Negro":"#161616","Rojo":"#d42a2a","Azul":"#1f5fd6","Amarillo":"#f2c200","Blanco":"#ffffff",
            "Verde":"#1f9d45","Gris":"#8a8f98","Café":"#7a4a1e","Naranja":"#f07c00",
            "Verde-amarillo":"linear-gradient(90deg,#1f9d45 50%,#f2c200 50%)"};
          function esc(t){return String(t).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});}
          function set(k,v){ sketchup.set_value(k, String(v)); }
          function opts(list,cur){return list.map(function(o){return '<option value="'+esc(o[0])+'"'+(String(o[0])===String(cur)?' selected':'')+'>'+esc(o[1])+'</option>';}).join('');}
          function sel(k,list,cur){return '<select onchange="set(\\''+k+'\\',this.value)">'+opts(list,cur)+'</select>';}
          function num(k,v,min,max,step,cls){return '<input type="number" class="'+(cls||'')+'" value="'+esc(v)+'" min="'+min+'" max="'+max+'" step="'+step+'" onchange="set(\\''+k+'\\',this.value)">';}
          function seg(k,list,cur){return '<div class="seg">'+list.map(function(o){return '<button class="'+(String(o[0])===String(cur)?'on':'')+'" onclick="set(\\''+k+'\\',\\''+o[0]+'\\')">'+esc(o[1])+'</button>';}).join('')+'</div>';}
          function sw(k,on,text){return '<label class="sw"><input type="checkbox" '+(on?'checked':'')+' onchange="set(\\''+k+'\\',this.checked)">'+text+'</label>';}
          function f(t){return '<label class="f">'+t+'</label>';}
          function render(st){
            S = st; var v = st.v, i = st.info, h = [];
            document.getElementById('ver').textContent = 'v'+st.version;
            h.push('<div class="card"><h2>Norma</h2>'+sel('profile',st.profiles,v.profile)+
              '<div class="sum">'+esc(i.code_summary)+'</div></div>');

            h.push('<div class="card"><h2>Tubería</h2>'+f('Tipo')+sel('type',st.types,v.type)+
              '<div class="hint">Norma de producto: '+esc(i.std)+'</div>'+
              f('Diámetro')+sel('size',st.sizes,v.size)+
              f('Instalación')+seg('install',[['surface','A la vista'],['embedded','Empotrada']],v.install)+
              '<div class="hint">'+(v.surface?'El tubo se apoya SOBRE muros, pisos y techos; en esquinas se separa de ambas caras.':'El tubo queda DENTRO del muro/losa y las cajas al ras.')+'</div>'+
              (i.is_emt? f('Uniones EMT')+seg('connection',[['setscrew','Tornillo (set-screw)'],['compression','Compresión']],v.connection):'')+
              '</div>');

            h.push('<div class="card"><h2>Curvas</h2>'+seg('bend_mode',[['field','Doblar el tubo'],['premade','Codo prefabricado']],v.bend_mode)+
              '<div class="hint">Cambia en vivo con Ctrl (Win) / Option (Mac) mientras dibujas.</div>'+
              f('Radio de curvatura (mm)')+num('bend_radius_mm',Math.round(v.bend_radius_mm*10)/10,10,5000,1)+
              '<div class="hint">Mínimo '+i.min_radius+' mm ('+esc(i.radius_ref)+') · <a onclick="sketchup.min_radius()">usar mínimo</a></div></div>');

            var boxOpts = st.boxes.map(function(g){return '<optgroup label="'+esc(g[0])+'">'+opts(g[1],v.box_key)+'</optgroup>';}).join('');
            h.push('<div class="card"><h2>Cajas</h2>'+f('Caja activa')+
              '<select onchange="set(\\'box_key\\',this.value)">'+boxOpts+'</select>'+
              f('Terminación en cajas')+sel('termination',[['std','Conector + boquilla aislante'],['gnd','Conector + boquilla de puesta a tierra'],['none','Sin accesorios']],v.termination)+
              sw('pull_boxes',v.pull_boxes,'Cajas de paso automáticas')+
              (v.pull_boxes?'<div class="hint">Inserta la caja activa cuando las curvas acumuladas superen '+num('max_bend_deg',v.max_bend_deg,90,720,45,'inl')+' °</div>':
                '<div class="hint">Al activarlo, se coloca una caja de paso cuando las curvas entre cajas superan el límite de la norma.</div>')+
              '</div>');

            var c = '<div class="card"><h2>Conductores</h2>'+f('Circuitos dentro del tubo')+num('circuits',v.circuits,0,12,1)+
              '<div class="hint">0 = sin cableado. Se usan para la ocupación del tubo y la lista de cable.</div>';
            if (Number(v.circuits) > 0) {
              c += '<div class="row"><div>'+f('Circuito')+sel('circuit',st.circuits,v.circuit)+'</div><div>'+f('Sistema')+sel('system',st.systems,v.system)+'</div></div>'+
                '<div class="row"><div>'+f('Calibre')+sel('wire_size',st.wire_sizes,v.wire_size)+'</div><div>'+f('Aislamiento')+sel('insulation',st.insulations,v.insulation)+'</div></div>'+
                sw('ground',v.ground,'Conductor de puesta a tierra')+
                (v.ground? '<div class="row"><div>'+sel('ground_size',[['same','Mismo calibre que las fases']].concat(st.wire_sizes),v.ground_size)+'</div></div>':'');
              var fl = i.fill;
              if (fl.pct !== null && fl.pct !== undefined) {
                var pct = Math.min(fl.pct/ (fl.limit*1.5) *100, 100), mark = fl.limit/(fl.limit*1.5)*100;
                c += '<div class="fill"><span>Ocupación ('+fl.count+' cond.)</span><b class="'+(fl.ok?'ok':'bad')+'">'+fl.pct+' % / '+fl.limit+' % '+(fl.ok?'✓':'✗')+'</b></div>'+
                  '<div class="meter"><i class="'+(fl.ok?'':'bad')+'" style="width:'+pct+'%"></i><s style="left:'+mark+'%"></s></div>'+
                  '<div class="hint">'+esc(i.fill_ref)+'</div>';
              }
              if (i.suggest) c += '<button class="btn" onclick="sketchup.suggest_size()">'+(fl.ok?'Diámetro mínimo que cumple: ':'Cambiar a ')+esc(i.suggest[1])+'</button>';
              c += '<div class="chips">'+i.conds.map(function(x){return '<span class="chip"><span class="dot" style="background:'+(COLORS[x.color]||'#ccc')+'"></span>'+esc(x.role)+' '+esc(x.label)+' · '+esc(x.color)+'</span>';}).join('')+'</div>';
            }
            h.push(c+'</div>');

            h.push('<details class="card"'+(window._adv?' open':'')+' ontoggle="window._adv=this.open"><summary>Avanzado</summary>'+
              '<div class="row"><div>'+f('Tramo comercial (m)')+num('stock_m',v.stock_m,0.5,12,0.1)+'</div><div>'+f('Facetas del tubo')+num('segments',v.segments,8,48,1)+'</div></div>'+
              '<div class="hint">Cada tramo comercial se dibuja como un tubo con su unión.</div>'+
              (v.surface? sw('straps',v.straps,'Soportes (abrazaderas) según norma')+
                '<div class="row"><div>'+f('Separación del muro (mm)')+num('standoff_mm',v.standoff_mm,0,200,1)+'</div><div></div></div>'
              : '<div class="row"><div>'+f('Recubrimiento (mm)')+num('cover_mm',v.cover_mm,0,100,1)+'</div><div></div></div>')+
              sw('check_updates',v.check_updates,'Avisar de nuevas versiones (1×/día)')+
              '</details>');
            document.getElementById('app').innerHTML = h.join('');
          }
          function flash(msg){ var f=document.getElementById('flash'); f.textContent=msg; f.style.opacity=1;
            clearTimeout(window._ft); window._ft=setTimeout(function(){f.style.opacity=0;},1100); }
          render(S);
        </script>
        </body></html>
      HTML
    end

    # ---- Materials (BOM) dialog -------------------------------------------

    def bom_mode
      Settings.get('bom_mode').to_s == 'optimized' ? :optimized : :pieces
    end

    def show_bom
      if @bom_dlg&.visible?
        update_bom(@bom_dlg)
        @bom_dlg.bring_to_front
        return
      end

      @bom_dlg = UI::HtmlDialog.new(
        dialog_title: 'SKP E-Plumb — Materiales',
        preferences_key: 'com.aaeion.skpeplumb.bom',
        scrollable: true, resizable: true,
        width: 820, height: 560, min_width: 480, min_height: 300,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      register_bom_callbacks(@bom_dlg)
      @bom_dlg.set_html(bom_dialog_html)
      @bom_dlg.show
    rescue StandardError => e
      report_error(e, 'Materiales')
    end

    def update_bom(dlg)
      model = Sketchup.active_model
      data = Bom.aggregate(model, bom_mode)
      review = Bom.review(model)
      dlg.execute_script("update(#{js_string(Bom.table_html(data))},#{js_string(Bom.review_html(review))}," \
                         "#{review.length},#{js_string(data[:mode].to_s)});")
    end

    def register_bom_callbacks(dlg)
      dlg.add_action_callback('ready') { |_ctx| update_bom(dlg); nil }
      dlg.add_action_callback('refresh') { |_ctx| update_bom(dlg); nil }
      dlg.add_action_callback('set_mode') do |_ctx, value|
        Settings.set('bom_mode', value.to_s)
        update_bom(dlg)
        nil
      end
      dlg.add_action_callback('export_csv') { |_ctx| export_bom(:csv); nil }
      dlg.add_action_callback('export_html') { |_ctx| export_bom(:html); nil }
      dlg.add_action_callback('select_pid') do |_ctx, pid|
        select_entity(pid.to_i)
        nil
      end
    end

    def select_entity(pid)
      model = Sketchup.active_model
      ent = model.find_entity_by_persistent_id(pid) if model.respond_to?(:find_entity_by_persistent_id)
      return unless ent&.valid?

      model.selection.clear
      model.selection.add(ent)
      model.active_view.zoom(ent)
    rescue StandardError
      nil
    end

    def export_bom(fmt)
      model = Sketchup.active_model
      data = Bom.aggregate(model, bom_mode)
      default = fmt == :csv ? 'Materiales_SKP_E_Plumb.csv' : 'Materiales_SKP_E_Plumb.html'
      path = UI.savepanel('Guardar lista de materiales', dir_hint, default)
      return unless path

      content = fmt == :csv ? "\uFEFF#{Bom.to_csv(data)}" : Bom.to_html(data, review: Bom.review(model))
      File.open(path, 'w:UTF-8') { |f| f.write(content) }
      UI.messagebox("Lista exportada:\n#{path}")
    rescue StandardError => e
      UI.messagebox("No se pudo exportar: #{e.message}")
    end

    def dir_hint
      model_path = Sketchup.active_model.path
      model_path.empty? ? nil : File.dirname(model_path)
    end

    def bom_dialog_html
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <style>
          body{font-family:"Segoe UI",-apple-system,Helvetica,Arial,sans-serif;margin:0;color:#1b1e24;background:#fff;font-size:13px}
          .bar{position:sticky;top:0;background:#1f5f99;color:#fff;padding:10px 14px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;z-index:2}
          .bar h1{font-size:15px;margin:0;flex:1 1 auto}
          .bar button{background:#fff;color:#1f5f99;border:0;border-radius:6px;padding:6px 11px;font-weight:600;cursor:pointer}
          .tabs{display:flex;gap:2px;padding:8px 14px 0;border-bottom:1px solid #dde2e8;background:#f3f5f8;position:sticky;top:48px;z-index:1;align-items:end}
          .tabs a{padding:7px 12px;border-radius:7px 7px 0 0;cursor:pointer;color:#445;text-decoration:none}
          .tabs a.on{background:#fff;border:1px solid #dde2e8;border-bottom-color:#fff;margin-bottom:-1px;color:#1f5f99;font-weight:600}
          .tabs .sp{flex:1}.tabs label{font-size:12px;margin-left:10px;cursor:pointer;padding-bottom:6px}
          .badge{background:#b42318;color:#fff;border-radius:9px;padding:0 6px;font-size:11px;margin-left:4px}
          .badge.zero{background:#1a7f37}
          .content{padding:14px}
          table{border-collapse:collapse;width:100%;font-size:13px}
          th,td{border:1px solid #dde2e8;padding:6px 8px;text-align:left}
          th{background:#eef3f8}
          tr:nth-child(even){background:#f8fafc}
          td.c{text-align:center}td.n{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
          td.std,td.d{color:#5b6472;font-size:12px}
          .empty{color:#889;font-style:italic}
          .rv{border:1px solid #dde2e8;border-radius:8px;padding:8px 12px;margin-bottom:8px}
          .rvh{display:flex;justify-content:space-between;gap:10px}
          .rv ul{margin:6px 0 0 18px;padding:0}.rv li{margin:3px 0}
          li.error{color:#b42318}li.warn{color:#9a6700}.ok{color:#1a7f37;font-weight:600}
          .note{color:#6b7380;font-size:11px;margin-top:12px}
        </style></head><body>
        <div class="bar">
          <h1>Lista de materiales</h1>
          <button onclick="sketchup.refresh()">↻ Actualizar</button>
          <button onclick="sketchup.export_csv()">Exportar CSV</button>
          <button onclick="sketchup.export_html()">Exportar HTML</button>
        </div>
        <div class="tabs">
          <a id="t1" class="on" onclick="tab(1)">Materiales</a>
          <a id="t2" onclick="tab(2)">Revisión normativa<span id="cnt" class="badge zero">0</span></a>
          <span class="sp"></span>
          <span style="font-size:12px;padding-bottom:6px">Tubos:</span>
          <label><input type="radio" name="m" id="m1" onclick="sketchup.set_mode('pieces')"> por tramos dibujados</label>
          <label><input type="radio" name="m" id="m2" onclick="sketchup.set_mode('optimized')"> optimizado (reutiliza retazos)</label>
        </div>
        <div class="content">
          <div id="p1"><div id="tbl"><p class="empty">Cargando…</p></div></div>
          <div id="p2" style="display:none"><div id="rev"></div>
            <div class="note">Revisa: curvas entre cajas (NEC/NTC 2050 3xx.26), ocupación de conductores
            (Cap. 9 Tabla 1), radio de curvatura (Cap. 9 Tabla 2) y longitud entre registros (IEC).
            Herramienta de apoyo: no reemplaza el diseño ni la inspección RETIE.</div></div>
        </div>
        <script>
          function tab(n){ [1,2].forEach(function(i){ document.getElementById('p'+i).style.display = i===n?'':'none';
            document.getElementById('t'+i).className = i===n?'on':''; }); }
          function update(tbl, rev, count, mode){
            document.getElementById('tbl').innerHTML = tbl;
            document.getElementById('rev').innerHTML = rev;
            var c = document.getElementById('cnt'); c.textContent = count; c.className = 'badge'+(count?'':' zero');
            document.getElementById(mode==='optimized'?'m2':'m1').checked = true;
          }
          sketchup.ready();
        </script>
        </body></html>
      HTML
    end

    # Show any failure in a message box so silent errors become reportable.
    def report_error(err, context)
      trace = (err.backtrace || [])[0, 6].join("\n")
      UI.messagebox("SKP E-Plumb — error en #{context}:\n\n#{err.class}: " \
                    "#{err.message}\n\n#{trace}")
    end

    # ---- About & What's New ----------------------------------------------

    # "What's new" for the given version (shown once after an update).
    def show_whatsnew(version)
      notes = Updater.changelog_notes(version)
      body = notes ? md_to_html(notes) : "<p>Versión <b>#{Bom.h(version)}</b> instalada.</p>"

      @whatsnew_dlg = UI::HtmlDialog.new(
        dialog_title: "SKP E-Plumb — Novedades v#{version}",
        preferences_key: 'com.aaeion.skpeplumb.whatsnew',
        scrollable: true, resizable: true,
        width: 520, height: 600, min_width: 360, min_height: 320,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg = @whatsnew_dlg
      dlg.add_action_callback('donate') { |_c| UI.openURL(Updater::DONATE_URL); nil }
      dlg.add_action_callback('close') { |_c| dlg.close; nil }
      dlg.set_html(info_html("Novedades — v#{version}", body, show_close: true))
      dlg.show
    rescue StandardError => e
      report_error(e, 'Novedades')
    end

    def show_about
      if @about_dlg&.visible?
        @about_dlg.bring_to_front
        return
      end

      body = <<~HTML
        <p><b>SKP E-Plumb</b> v#{SkpEPlumb::VERSION}</p>
        <p>Modelador de canalizaciones eléctricas y lista de materiales para SketchUp:
        EMT, IMC, RMC, PVC y PVC métrico IEC, con uniones, codos, curvas de campo,
        boquillas, contratuercas, soportes, cajas y conductores.</p>
        <p>Perfiles de norma: <b>NTC 2050 + RETIE</b> (Colombia), <b>NEC</b> (EE.UU.) e
        <b>IEC 60364</b>. Herramienta de apoyo: no reemplaza el diseño de un profesional
        ni la inspección de la instalación.</p>
        <p>Licencia <b>GPL-3.0-or-later</b> · © 2026 AA-EION</p>
        <p><a href="#" onclick="sketchup.repo();return false">github.com/#{Updater::REPO}</a></p>
      HTML

      @about_dlg = UI::HtmlDialog.new(
        dialog_title: 'SKP E-Plumb — Acerca de',
        preferences_key: 'com.aaeion.skpeplumb.about',
        scrollable: true, resizable: true,
        width: 460, height: 460, min_width: 340, min_height: 280,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg = @about_dlg
      dlg.add_action_callback('donate') { |_c| UI.openURL(Updater::DONATE_URL); nil }
      dlg.add_action_callback('updates') { |_c| Updater.check(interactive: true); nil }
      dlg.add_action_callback('repo') { |_c| UI.openURL("https://github.com/#{Updater::REPO}"); nil }
      dlg.add_action_callback('close') { |_c| dlg.close; nil }
      dlg.set_html(info_html('Acerca de', body, show_updates: true))
      dlg.show
    rescue StandardError => e
      report_error(e, 'Acerca de')
    end

    # Shared page shell for About / What's New with a PayPal donate button.
    def info_html(title, body_html, show_close: false, show_updates: false)
      close_btn = show_close ? '<button class="ghost" onclick="sketchup.close()">Cerrar</button>' : ''
      upd_btn = show_updates ? '<button class="ghost" onclick="sketchup.updates()">Buscar actualizaciones</button>' : ''
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{font-family:"Segoe UI",-apple-system,Helvetica,Arial,sans-serif;margin:0;color:#1b1e24;background:#f3f5f8;font-size:13px}
          header{background:#1f5f99;color:#fff;padding:12px 16px}
          header h1{margin:0;font-size:15px}
          .wrap{padding:14px 16px}
          .wrap p{margin:0 0 10px;line-height:1.45}
          .h{font-weight:700;margin:12px 0 4px}
          .li{margin:2px 0 2px 6px}
          .sp{height:6px}
          code{background:#e6ebf1;padding:1px 4px;border-radius:4px;font-size:12px}
          a{color:#1f5f99}
          .bar{position:sticky;bottom:0;background:#f3f5f8;border-top:1px solid #dde2e8;padding:12px 16px;display:flex;gap:8px;flex-wrap:wrap}
          button{padding:9px 12px;border:0;border-radius:6px;font-size:13px;font-weight:600;cursor:pointer}
          .paypal{background:#0070ba;color:#fff}
          .ghost{background:#e2e7ee;color:#222}
        </style></head><body>
        <header><h1>SKP E-Plumb — #{Bom.h(title)}</h1></header>
        <div class="wrap">#{body_html}</div>
        <div class="bar">
          <button class="paypal" onclick="sketchup.donate()">❤ Donar con PayPal</button>
          #{upd_btn}#{close_btn}
        </div>
        </body></html>
      HTML
    end

    # Minimal markdown -> HTML for the changelog block (headings, bullets, bold).
    def md_to_html(md)
      md.to_s.lines.map do |raw|
        line = Bom.h(raw.rstrip)
        if line =~ /^\#\#\#\s*(.+)/
          "<div class='h'>#{md_inline(Regexp.last_match(1))}</div>"
        elsif line =~ /^\s*[-*]\s+(.+)/
          "<div class='li'>• #{md_inline(Regexp.last_match(1))}</div>"
        elsif line.strip.empty?
          "<div class='sp'></div>"
        else
          "<div>#{md_inline(line)}</div>"
        end
      end.join
    end

    def md_inline(str)
      str.gsub(/\*\*(.+?)\*\*/, '<b>\1</b>').gsub(/`(.+?)`/, '<code>\1</code>')
    end

    # ---- helpers ----------------------------------------------------------

    # JSON safe to embed inside a <script> block.
    def safe_json(obj)
      obj.to_json.gsub('</', '<\/')
    end

    # Encode a Ruby string as a safe JS string literal for execute_script.
    def js_string(str)
      str.to_s.to_json.gsub('</', '<\/')
    rescue StandardError
      escaped = str.to_s.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")
                   .gsub("\n", '\\n').gsub("\r", '')
      "'#{escaped}'"
    end
  end
end
