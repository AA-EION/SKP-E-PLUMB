# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Bom
  # ---------------------------------------------------------------------------
  # The Bill of Materials engine. Every part the builder creates carries an
  # attribute dictionary (DICT); run containers carry their conductors and
  # code statistics (RUN_DICT). The BOM is derived *from the model*, so if the
  # user deletes a pipe or an elbow the BOM updates automatically the next time
  # it is generated.
  # ===========================================================================
  module Bom
    DICT = 'SKP_E_PLUMB'
    RUN_DICT = 'SKP_E_PLUMB_RUN'

    # Part categories.
    PART_PIPE        = 'pipe'
    PART_COUPLING    = 'coupling'
    PART_CONNECTOR   = 'connector'
    PART_ELBOW       = 'elbow'   # generic premade elbow, angle in 'angle'
    PART_ELBOW90     = 'elbow90' # 1.x models
    PART_ELBOW45     = 'elbow45' # 1.x models
    PART_BUSHING_STD = 'bushing_std'
    PART_BUSHING_GND = 'bushing_gnd'
    PART_LOCKNUT     = 'locknut'
    PART_BOX         = 'box'
    PART_STRAP       = 'strap'
    PART_WIRE        = 'wire'

    # Free conductor length left in each box / termination, per conductor
    # (NEC / NTC 2050 300.14 asks for at least 150 mm).
    WIRE_SLACK_M = 0.2

    module_function

    # Write the plugin's attributes on a group/component instance.
    def tag(entity, attrs)
      attrs.each { |k, v| entity.set_attribute(DICT, k.to_s, v) }
      entity
    end

    def tagged?(entity)
      entity.respond_to?(:attribute_dictionary) &&
        !entity.attribute_dictionary(DICT).nil?
    end

    def run_container?(entity)
      entity.respond_to?(:attribute_dictionary) &&
        !entity.attribute_dictionary(RUN_DICT).nil?
    end

    def read(entity, dict = DICT)
      d = entity.attribute_dictionary(dict)
      return nil unless d

      h = {}
      d.each { |k, v| h[k] = v }
      h
    end

    # Walk the model collecting every tagged entity's attribute hash, plus one
    # row per conductor of every run.
    def collect_raw(model = Sketchup.active_model)
      rows = []
      walk(model.entities, rows)
      rows
    end

    def walk(entities, rows)
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

        if tagged?(e)
          rows << read(e)
          next # do not descend into a tagged part
        end
        rows.concat(wire_rows(read(e, RUN_DICT))) if run_container?(e)

        sub = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        walk(sub, rows)
      end
    end

    # One raw row per conductor of a run (from its stored metadata).
    def wire_rows(meta)
      return [] unless meta && meta['w_size'].is_a?(Array)

      len = meta['run_len_m'].to_f + WIRE_SLACK_M * meta['terms'].to_i
      meta['w_size'].each_index.map do |i|
        { 'part' => PART_WIRE, 'size' => meta['w_size'][i].to_s, 'ins' => meta['w_ins'][i].to_s,
          'color' => meta['w_color'][i].to_s, 'role' => meta['w_role'][i].to_s, 'length_m' => len }
      end
    end

    # Aggregate the model into BOM line items.
    def aggregate(model = Sketchup.active_model, mode = :pieces)
      summarize(collect_raw(model), mode)
    end

    # Pure aggregation of raw attribute rows into BOM line items grouped by
    # material key. Kept free of the SketchUp API so it can be unit tested.
    # `mode` controls how tubes are counted:
    #   :pieces    -> each drawn stock piece is one tube (no offcut reuse)
    #   :optimized -> ceil(total metres / stock) over the WHOLE model per
    #                 type/size (reuses offcuts between runs)
    # Returns { lines: [...], generated_at:, part_total:, mode: }.
    def summarize(raw, mode = :pieces)
      mode = mode.to_sym
      pipe_len = Hash.new(0.0)
      pipe_count = Hash.new(0)
      pipe_stock = {}
      wire_len = Hash.new(0.0)
      wire_count = Hash.new(0)
      counts = Hash.new(0)
      meta = {}
      parts = 0

      raw.each do |r|
        part = r['part']
        type = r['type']
        size = r['size']

        case part
        when PART_PIPE
          parts += 1
          key = "PIPE|#{type}|#{size}"
          pipe_len[key] += (r['length_mm'] || 0.0) / 1000.0
          pipe_count[key] += 1
          pipe_stock[key] = (r['stock_m'] || 3.0).to_f
          meta[key] ||= { category: 'Tubería', desc: r['desc'], type: type, size: size,
                          std: r['std'] || type_std(type) }
        when PART_WIRE
          key = "WIRE|#{r['ins']}|#{r['size']}|#{r['color']}"
          wire_len[key] += r['length_m'].to_f
          wire_count[key] += 1
          meta[key] ||= wire_meta(r)
        else
          parts += 1
          key = "#{part}|#{type}|#{size}|#{r['box_key']}|#{r['angle']}"
          counts[key] += (r['qty'] || 1)
          meta[key] ||= { category: category_label(part, r), desc: r['desc'],
                          type: type, size: size, std: part_std(part, r) }
        end
      end

      lines = []
      pipe_len.each do |key, metres|
        stock = pipe_stock[key]
        tubes = if mode == :optimized && stock.positive?
                  (metres / stock - 1.0e-9).ceil
                else
                  pipe_count[key]
                end
        note = mode == :optimized ? 'optimizado' : "#{pipe_count[key]} tramo(s)"
        m = meta[key]
        lines << line(m, tubes, 'tubo(s)', format('%.2f m totales · %s (tramo %.1f m)', metres, note, stock))
      end

      wire_len.each do |key, metres|
        m = meta[key]
        lines << line(m, metres.ceil, 'm',
                      format('%.1f m en %d tramo(s) · incluye %.1f m por caja', metres, wire_count[key],
                             WIRE_SLACK_M))
      end

      counts.each do |key, qty|
        lines << line(meta[key], qty, 'pza(s)', '')
      end

      lines.sort_by! { |l| [order_index(l[:category]), l[:type].to_s, l[:size].to_s, l[:description].to_s] }
      { lines: lines, generated_at: Time.now, part_total: parts, mode: mode }
    end

    def line(m, qty, unit, detail)
      { category: m[:category], description: m[:desc], type: m[:type], size: m[:size],
        std: m[:std].to_s, qty: qty, unit: unit, detail: detail }
    end

    def wire_meta(r)
      ins = r['ins']
      label = (defined?(Codes) && Codes::INSULATION[ins] && Codes::INSULATION[ins][:label]) || ins
      size = defined?(Codes) ? Codes.wire_label(r['size'], ins) : r['size']
      std = defined?(Codes) && Codes::INSULATION[ins] ? Codes::INSULATION[ins][:std] : ''
      { category: 'Conductor', desc: "Cable #{label} #{size} — #{r['color']}", type: ins,
        size: size, std: std }
    end

    def type_std(type)
      defined?(Catalog) && Catalog::TYPES[type] ? Catalog::TYPES[type][:std].to_s : ''
    end

    def part_std(part, r)
      return r['std'].to_s if r['std']
      return (Catalog::BOXES[r['box_key']] || {})[:std].to_s if part == PART_BOX && defined?(Catalog)

      [PART_COUPLING, PART_ELBOW, PART_ELBOW90, PART_ELBOW45].include?(part) ? type_std(r['type']) : ''
    end

    def category_label(part, r = {})
      case part
      when PART_COUPLING    then 'Unión / copla'
      when PART_CONNECTOR   then 'Conector a caja'
      when PART_ELBOW
        a = r['angle'].to_f
        "Codo #{a % 1 == 0 ? a.round : a}°"
      when PART_ELBOW90     then 'Codo 90°'
      when PART_ELBOW45     then 'Codo 45°'
      when PART_BUSHING_STD then 'Boquilla aislante'
      when PART_BUSHING_GND then 'Boquilla puesta a tierra'
      when PART_LOCKNUT     then 'Contratuerca'
      when PART_BOX         then 'Caja'
      when PART_STRAP       then 'Soporte'
      else 'Otro'
      end
    end

    ORDER = ['Tubería', 'Unión / copla', 'Codo 90°', 'Codo 45°', 'Codo 30°', 'Codo 22.5°',
             'Conector a caja', 'Contratuerca', 'Boquilla aislante', 'Boquilla puesta a tierra',
             'Soporte', 'Caja', 'Conductor', 'Otro'].freeze

    def order_index(cat)
      ORDER.index(cat) || ORDER.length
    end

    # ---- Code review --------------------------------------------------------

    # Review every run in the model against its profile.
    # Returns [{ pid:, name:, issues: [{level:, msg:}] }] (runs with issues only).
    def review(model = Sketchup.active_model)
      out = []
      each_run(model.entities) do |e, meta|
        issues = review_meta(meta)
        next if issues.empty?

        pid = e.respond_to?(:persistent_id) ? e.persistent_id : 0
        out << { pid: pid, name: e.name.to_s, issues: issues }
      end
      out
    end

    def each_run(entities, &block)
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if tagged?(e)

        if run_container?(e)
          block.call(e, read(e, RUN_DICT))
          next
        end
        sub = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        each_run(sub, &block)
      end
    end

    # Pure: review one run's stored metadata.
    def review_meta(meta)
      return [] unless meta && defined?(Codes)

      opts = parse_opts(meta['opts_json'])
      conds = (meta['w_size'] || []).each_index.map do |i|
        { size: meta['w_size'][i].to_s, ins: meta['w_ins'][i].to_s }
      end
      stats = {
        type: meta['type'], size: meta['size'], max_deg: meta['max_deg'] && meta['max_deg'].to_f,
        max_len_m: meta['max_len_m'] && meta['max_len_m'].to_f,
        limit_deg: opts['pull_boxes'] ? opts['max_bend_deg'] : nil,
        fill: conds.empty? ? nil : Codes.fill(meta['type'], meta['size'], conds), conds: conds,
        bend_radius_mm: opts['bend_radius_mm'] && opts['bend_radius_mm'].to_f,
        bend_mode: opts['bend_mode']
      }
      Codes.review(meta['profile'].to_s.empty? ? 'NTC' : meta['profile'], stats)
    end

    def parse_opts(json)
      return {} unless json && defined?(JSON)

      JSON.parse(json)
    rescue StandardError
      {}
    end

    # ---- Export -----------------------------------------------------------

    def to_csv(data)
      rows = ['Categoria,Descripcion,Tipo,Medida,Norma,Cantidad,Unidad,Detalle']
      data[:lines].each do |l|
        rows << [
          csv(l[:category]), csv(l[:description]), csv(l[:type]), csv(l[:size]),
          csv(l[:std]), l[:qty], csv(l[:unit]), csv(l[:detail])
        ].join(',')
      end
      rows.join("\n")
    end

    def csv(value)
      s = value.to_s
      s = %("#{s.gsub('"', '""')}") if s.match?(/[",\n]/)
      s
    end

    # Just the <table> markup, reused by both the export file and the dialog.
    def table_html(data)
      if data[:lines].empty?
        return "<p class='empty'>Aún no hay materiales. Dibuja tuberías o " \
               'coloca cajas para poblar la lista.</p>'
      end

      rows = data[:lines].map do |l|
        "<tr><td>#{h(l[:category])}</td><td>#{h(l[:description])}</td>" \
          "<td class='c'>#{h(l[:size])}</td><td class='c std'>#{h(l[:std])}</td>" \
          "<td class='n'>#{l[:qty]}</td><td class='c'>#{h(l[:unit])}</td>" \
          "<td class='d'>#{h(l[:detail])}</td></tr>"
      end.join("\n")

      <<~TABLE
        <table><thead><tr><th>Categoría</th><th>Descripción</th><th>Medida</th>
        <th>Norma</th><th>Cant.</th><th>Unidad</th><th>Detalle</th></tr></thead>
        <tbody>
        #{rows}
        </tbody></table>
      TABLE
    end

    def review_html(items)
      if items.empty?
        return "<p class='ok'>✓ Sin observaciones: curvas entre cajas, ocupación y " \
               'radios dentro de los límites.</p>'
      end

      items.map do |it|
        msgs = it[:issues].map do |x|
          "<li class='#{x[:level]}'>#{h(x[:msg])}</li>"
        end.join
        "<div class='rv'><div class='rvh'><b>#{h(it[:name])}</b> " \
          "<a href='#' onclick='sketchup.select_pid(#{it[:pid].to_i});return false'>Ver en el modelo</a>" \
          "</div><ul>#{msgs}</ul></div>"
      end.join
    end

    def to_html(data, title: 'Lista de materiales — SKP E-Plumb', review: nil)
      rv = review ? "<h2>Revisión normativa</h2>#{review_html(review).gsub(/<a .*?<\/a>/, '')}" : ''
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <title>#{h(title)}</title>
        <style>
          body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:24px;color:#1b1e24}
          h1{font-size:18px;margin:0 0 4px}h2{font-size:15px;margin:22px 0 8px}
          .sub{color:#667;font-size:12px;margin-bottom:16px}
          table{border-collapse:collapse;width:100%;font-size:13px}
          th,td{border:1px solid #d4d7dd;padding:6px 8px;text-align:left}
          th{background:#1f5f99;color:#fff}
          tr:nth-child(even){background:#f4f6f9}
          td.c{text-align:center}td.n{text-align:right;font-variant-numeric:tabular-nums}
          td.std,td.d{color:#556;font-size:12px}
          .foot{margin-top:12px;color:#889;font-size:11px}
          .empty{color:#889;font-style:italic}
          li.error{color:#b42318}li.warn{color:#9a6700}.ok{color:#1a7f37}
        </style></head><body>
        <h1>Lista de materiales</h1>
        <div class="sub">SKP E-Plumb · generado #{data[:generated_at].strftime('%Y-%m-%d %H:%M')}</div>
        #{table_html(data)}
        #{rv}
        <div class="foot">Total de piezas modeladas: #{data[:part_total]}. Herramienta de
        estimación: verifique con el código aplicable y un profesional.</div>
        </body></html>
      HTML
    end

    def h(value)
      value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
           .gsub('"', '&quot;').gsub("'", '&#39;')
    end
  end
end
