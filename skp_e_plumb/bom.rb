# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Bom
  # ---------------------------------------------------------------------------
  # The Bill of Materials engine. Every part the builder creates carries an
  # attribute dictionary (DICT). The BOM is derived *from the model*, so if the
  # user deletes a pipe or an elbow the BOM updates automatically the next time
  # it is generated. Pipe quantities respect the commercial stock length: the
  # metres of raceway are summed and divided by the stock length (rounded up)
  # to obtain the number of tubes to purchase.
  # ===========================================================================
  module Bom
    DICT = 'SKP_E_PLUMB'

    # Part categories.
    PART_PIPE        = 'pipe'
    PART_COUPLING    = 'coupling'
    PART_CONNECTOR   = 'connector'
    PART_ELBOW90     = 'elbow90'
    PART_ELBOW45     = 'elbow45'
    PART_BUSHING_STD = 'bushing_std'
    PART_BUSHING_GND = 'bushing_gnd'
    PART_LOCKNUT     = 'locknut'
    PART_BOX         = 'box'

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

    def read(entity)
      dict = entity.attribute_dictionary(DICT)
      return nil unless dict

      h = {}
      dict.each { |k, v| h[k] = v }
      h
    end

    # Walk the model collecting every tagged entity's attribute hash.
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

        sub = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        walk(sub, rows)
      end
    end

    # Aggregate the model into BOM line items. Returns { lines:, ... }.
    def aggregate(model = Sketchup.active_model)
      summarize(collect_raw(model))
    end

    # Pure aggregation of raw attribute rows into BOM line items grouped by
    # material key. Kept free of the SketchUp API so it can be unit tested.
    # Returns { lines: [...], generated_at: Time, part_total: n }.
    def summarize(raw)
      pipe_len = Hash.new(0.0)  # key -> summed metres
      pipe_stock = {}           # key -> stock_m
      counts = Hash.new(0)      # key -> pcs
      meta   = {}               # key -> descriptor hash

      raw.each do |r|
        part = r['part']
        type = r['type']
        size = r['size']
        desc = r['desc']

        if part == PART_PIPE
          key = "PIPE|#{type}|#{size}"
          pipe_len[key] += (r['length_mm'] || 0.0) / 1000.0
          pipe_stock[key] = (r['stock_m'] || 3.0)
          meta[key] ||= { category: 'Tubería', desc: desc, type: type, size: size }
        else
          key = "#{part}|#{type}|#{size}|#{r['box_key']}"
          counts[key] += (r['qty'] || 1)
          meta[key] ||= { category: category_label(part), desc: desc,
                          type: type, size: size }
        end
      end

      lines = []

      pipe_len.each do |key, metres|
        stock = pipe_stock[key]
        tubes = stock.to_f > 0 ? (metres / stock).ceil : 0
        m = meta[key]
        lines << {
          category: m[:category],
          description: m[:desc],
          type: m[:type],
          size: m[:size],
          qty: tubes,
          unit: 'tubo(s)',
          detail: format('%.2f m (tramo %.1f m)', metres, stock)
        }
      end

      counts.each do |key, qty|
        m = meta[key]
        lines << {
          category: m[:category],
          description: m[:desc],
          type: m[:type],
          size: m[:size],
          qty: qty,
          unit: 'pza(s)',
          detail: ''
        }
      end

      lines.sort_by! { |l| [order_index(l[:category]), l[:type].to_s, l[:size].to_s] }
      { lines: lines, generated_at: Time.now, part_total: raw.length }
    end

    def category_label(part)
      case part
      when PART_COUPLING    then 'Copla / Unión'
      when PART_CONNECTOR   then 'Conector a caja'
      when PART_ELBOW90     then 'Codo 90°'
      when PART_ELBOW45     then 'Codo 45°'
      when PART_BUSHING_STD then 'Bushing aislante'
      when PART_BUSHING_GND then 'Bushing aterrizaje'
      when PART_LOCKNUT     then 'Contratuerca'
      when PART_BOX         then 'Caja'
      else 'Otro'
      end
    end

    ORDER = ['Tubería', 'Copla / Unión', 'Codo 90°', 'Codo 45°',
             'Conector a caja', 'Contratuerca', 'Bushing aislante',
             'Bushing aterrizaje', 'Caja', 'Otro'].freeze

    def order_index(cat)
      i = ORDER.index(cat)
      i || ORDER.length
    end

    # ---- Export -----------------------------------------------------------

    def to_csv(data)
      rows = ['Categoria,Descripcion,Tipo,Medida,Cantidad,Unidad,Detalle']
      data[:lines].each do |l|
        rows << [
          csv(l[:category]), csv(l[:description]), csv(l[:type]),
          csv(l[:size]), l[:qty], csv(l[:unit]), csv(l[:detail])
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
               'coloca cajas para poblar el BOM.</p>'
      end

      rows = data[:lines].map do |l|
        "<tr><td>#{h(l[:category])}</td><td>#{h(l[:description])}</td>" \
          "<td class='c'>#{h(l[:type])}</td><td class='c'>#{h(l[:size])}</td>" \
          "<td class='n'>#{l[:qty]}</td><td class='c'>#{h(l[:unit])}</td>" \
          "<td>#{h(l[:detail])}</td></tr>"
      end.join("\n")

      <<~TABLE
        <table><thead><tr><th>Categoría</th><th>Descripción</th><th>Tipo</th>
        <th>Medida</th><th>Cant.</th><th>Unidad</th><th>Detalle</th></tr></thead>
        <tbody>
        #{rows}
        </tbody></table>
      TABLE
    end

    def to_html(data, title: 'BOM — SKP E-Plumb')
      <<~HTML
        <!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
        <title>#{h(title)}</title>
        <style>
          body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:24px;color:#1b1e24}
          h1{font-size:18px;margin:0 0 4px}
          .sub{color:#667;font-size:12px;margin-bottom:16px}
          table{border-collapse:collapse;width:100%;font-size:13px}
          th,td{border:1px solid #d4d7dd;padding:6px 8px;text-align:left}
          th{background:#2b6cb0;color:#fff}
          tr:nth-child(even){background:#f4f6f9}
          td.c{text-align:center}td.n{text-align:right;font-variant-numeric:tabular-nums}
          .foot{margin-top:12px;color:#889;font-size:11px}
          .empty{color:#889;font-style:italic}
        </style></head><body>
        <h1>Lista de materiales (BOM)</h1>
        <div class="sub">SKP E-Plumb · generado #{data[:generated_at].strftime('%Y-%m-%d %H:%M')}</div>
        #{table_html(data)}
        <div class="foot">Total de piezas modeladas: #{data[:part_total]}</div>
        </body></html>
      HTML
    end

    def h(value)
      value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
    end
  end
end
