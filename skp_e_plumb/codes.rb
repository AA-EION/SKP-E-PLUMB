# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Codes
  # ---------------------------------------------------------------------------
  # Electrical-code knowledge used to check and complete a design. Pure Ruby
  # (no SketchUp API) so it is unit tested offline.
  #
  #  * Profiles: NTC 2050 + RETIE (Colombia), NEC (USA), IEC 60364.
  #    NTC 2050 (2nd update, 2020) mirrors NEC 2017 article numbering, and
  #    RETIE 2024 (Res. 40117) requires installations to follow NTC 2050.
  #  * Bends between pull points: NEC/NTC 358.26 (EMT), 342.26 (IMC),
  #    344.26 (RMC), 352.26 (PVC) — max. 360° total. IEC 60364 sets no fixed
  #    value; the IEC profile uses a common reference practice (3 × 90° and
  #    15 m between draw-in points, e.g. REBT ITC-BT-21).
  #  * Conduit fill: NEC/NTC Chapter 9, Table 1 (53 % / 31 % / 40 %) with
  #    conductor areas from Table 5 (THHN, THW) and conduit areas from Table 4.
  #    IEC conductor data (H07V, IEC 60227-3) uses maximum outer diameters.
  #  * Supports: NEC/NTC 358.30, 342.30, 344.30 (within 0.9 m of each box and
  #    every 3 m) and Table 352.30 for PVC. IEC profile: IET On-Site Guide
  #    (BS 7671) spacing, used as a reference.
  #  * Conductor colours: RETIE 2024 (Libro 3, Tabla 3.5), NEC 200.6/250.119
  #    (+ customary phase colours) and IEC 60445.
  # ===========================================================================
  module Codes
    PROFILES = {
      'NTC' => {
        label: 'NTC 2050 + RETIE (Colombia)', short: 'NTC 2050 / RETIE',
        max_bend_deg: 360, max_len_m: 0, colors: :retie, units: :awg,
        insulation: 'THHN', default_type: 'EMT', code: 'NTC 2050'
      },
      'NEC' => {
        label: 'NEC (Estados Unidos)', short: 'NEC',
        max_bend_deg: 360, max_len_m: 0, colors: :nec, units: :awg,
        insulation: 'THHN', default_type: 'EMT', code: 'NEC'
      },
      'IEC' => {
        label: 'IEC 60364 (internacional)', short: 'IEC 60364',
        max_bend_deg: 270, max_len_m: 15, colors: :iec, units: :mm2,
        insulation: 'H07V', default_type: 'PVCM', code: 'IEC 60364'
      }
    }.freeze
    PROFILE_KEYS = PROFILES.keys.freeze

    # NEC / NTC 2050 article per raceway type (bends: .26, supports: .30).
    ARTICLE = { 'EMT' => '358', 'IMC' => '342', 'GALV' => '344', 'PVC' => '352' }.freeze

    # ---- conductors ----------------------------------------------------------
    AWG_SIZES = %w[14 12 10 8 6 4 3 2 1 1/0 2/0 3/0 4/0 250 300 350 400 500].freeze
    MM2_SIZES = %w[1.5 2.5 4 6 10 16 25 35 50 70 95 120].freeze

    # Approximate area including insulation (mm²) — NEC Ch.9 Table 5.
    THHN_AREA = {
      '14' => 6.258, '12' => 8.581, '10' => 13.61, '8' => 23.61, '6' => 32.71,
      '4' => 53.16, '3' => 62.77, '2' => 74.71, '1' => 100.8, '1/0' => 119.7,
      '2/0' => 143.4, '3/0' => 172.8, '4/0' => 208.8, '250' => 256.1,
      '300' => 297.3, '350' => 338.2, '400' => 378.3, '500' => 456.3
    }.freeze
    THW_AREA = {
      '14' => 8.968, '12' => 11.68, '10' => 15.68, '8' => 28.19, '6' => 46.84,
      '4' => 62.77, '3' => 73.16, '2' => 86.00, '1' => 122.6, '1/0' => 143.4,
      '2/0' => 169.3, '3/0' => 201.1, '4/0' => 239.9, '250' => 296.5,
      '300' => 340.7, '350' => 384.4, '400' => 427.0, '500' => 509.7
    }.freeze
    # H07V-R/U maximum outer diameter (mm), IEC 60227-3 (approximate).
    H07V_OD = {
      '1.5' => 3.4, '2.5' => 4.2, '4' => 4.8, '6' => 5.4, '10' => 6.8, '16' => 8.0,
      '25' => 9.8, '35' => 11.0, '50' => 13.0, '70' => 15.0, '95' => 17.0, '120' => 19.0
    }.freeze
    H07V_AREA = H07V_OD.transform_values { |d| (Math::PI / 4.0 * d * d).round(2) }.freeze

    INSULATION = {
      'THHN' => { label: 'THHN / THWN-2', units: :awg, std: 'UL 83', area: THHN_AREA },
      'THW'  => { label: 'THW / THW-2', units: :awg, std: 'UL 83', area: THW_AREA },
      'H07V' => { label: 'H07V-R/U (IEC)', units: :mm2, std: 'IEC 60227-3', area: H07V_AREA }
    }.freeze

    CIRCUITS = {
      '1F+N' => { phases: 1, neutral: true,  label: 'Monofásico 1F + N' },
      '2F'   => { phases: 2, neutral: false, label: 'Bifásico 2F' },
      '2F+N' => { phases: 2, neutral: true,  label: 'Bifásico 2F + N' },
      '3F'   => { phases: 3, neutral: false, label: 'Trifásico 3F' },
      '3F+N' => { phases: 3, neutral: true,  label: 'Trifásico 3F + N' }
    }.freeze

    SYSTEMS = {
      '120' => { label: '1F 120 V', max_phases: 1 },
      '240' => { label: '1F 120/240 V', max_phases: 2 },
      '208' => { label: '3F 208/120 V', max_phases: 3 },
      '480' => { label: '3F 480/277 V', max_phases: 3 }
    }.freeze

    PHASE_COLORS = {
      retie: { '120' => %w[Negro], '240' => %w[Negro Rojo], '208' => %w[Amarillo Azul Rojo],
               '480' => %w[Café Naranja Amarillo] },
      nec:   { '120' => %w[Negro], '240' => %w[Negro Rojo], '208' => %w[Negro Rojo Azul],
               '480' => %w[Café Naranja Amarillo] },
      iec:   Hash.new(%w[Café Negro Gris])
    }.freeze

    module_function

    def profile(key)
      PROFILES[key] || PROFILES['NTC']
    end

    def sizes_for_units(units)
      units == :mm2 ? MM2_SIZES : AWG_SIZES
    end

    def insulation(key)
      INSULATION[key] || INSULATION['THHN']
    end

    def wire_label(size, ins_key = 'THHN')
      return "#{size} mm²" if insulation(ins_key)[:units] == :mm2

      size.to_s.to_i >= 250 ? "#{size} kcmil" : "#{size} AWG"
    end

    def wire_area_mm2(size, ins_key)
      insulation(ins_key)[:area][size.to_s]
    end

    # Colour of each conductor role for a profile/system.
    def colors(profile_key, system)
      scheme = profile(profile_key)[:colors]
      phases = PHASE_COLORS[scheme][system.to_s] || PHASE_COLORS[scheme]['208']
      neutral = if scheme == :iec then 'Azul'
                elsif system.to_s == '480' then 'Gris'
                else 'Blanco'
                end
      ground = scheme == :iec ? 'Verde-amarillo' : 'Verde'
      { phases: phases, neutral: neutral, ground: ground }
    end

    # Expand a wiring spec into individual conductors:
    #   [{ role:, size:, ins:, color: }, ...]
    # spec keys: 'circuit', 'circuits', 'wire_size', 'ground' (bool),
    # 'ground_size' ('same' or a size), 'insulation', 'system', 'profile'.
    def conductors(spec)
      n_circ = spec['circuits'].to_i
      return [] if n_circ <= 0

      circ = CIRCUITS[spec['circuit']] || CIRCUITS['1F+N']
      sys = SYSTEMS[spec['system'].to_s] || SYSTEMS['208']
      phases = [circ[:phases], sys[:max_phases]].min
      ins = spec['insulation'] || 'THHN'
      size = spec['wire_size'].to_s
      cols = colors(spec['profile'], spec['system'])
      out = []
      n_circ.times do |c|
        phases.times do |p|
          # Successive single-phase circuits rotate through the phases so the
          # load is balanced (and each keeps its assigned phase colour).
          color = cols[:phases][(c + p) % cols[:phases].length]
          out << { role: 'Fase', size: size, ins: ins, color: color }
        end
        out << { role: 'Neutro', size: size, ins: ins, color: cols[:neutral] } if circ[:neutral]
      end
      if truthy(spec['ground'])
        gsize = spec['ground_size'].to_s
        gsize = size if gsize.empty? || gsize == 'same'
        out << { role: 'Tierra', size: gsize, ins: ins, color: cols[:ground] }
      end
      out
    end

    # NEC / NTC Chapter 9 Table 1 maximum fill for n conductors (%).
    def fill_limit_pct(count)
      return 53 if count == 1
      return 31 if count == 2

      40
    end

    # Conduit fill for a set of conductors. Returns
    #   { count:, wires_mm2:, conduit_mm2:, pct:, limit:, ok: } (pct nil if unknown).
    def fill(type, size, conds)
      area = Catalog.area_mm2(type, size)
      wires = conds.sum { |c| wire_area_mm2(c[:size], c[:ins]) || 0.0 }
      limit = fill_limit_pct(conds.length)
      pct = area && area.positive? ? (wires / area * 100.0) : nil
      { count: conds.length, wires_mm2: wires.round(1), conduit_mm2: area,
        pct: pct && pct.round(1), limit: limit, ok: pct.nil? || conds.empty? || pct <= limit + 1.0e-9 }
    end

    # Smallest size of `type` whose fill is within the limit, or nil.
    def min_size(type, conds)
      return nil if conds.empty?

      Catalog.sizes_for(type).find { |sz| fill(type, sz, conds)[:ok] }
    end

    # ---- supports / straps --------------------------------------------------

    # Distance from a box/termination to the first support (m). NEC/NTC
    # require ≤ 0.9 m; 0.3 m is used as good practice.
    STRAP_END_M = 0.3

    # Maximum support spacing (m) for a raceway type/size under a profile.
    def strap_spacing_m(profile_key, type, size)
      od = Catalog.od_mm(type, size)
      if profile_key == 'IEC' || Catalog.metric?(type)
        steel = %w[EMT IMC GALV].include?(type)
        return steel ? iec_steel_spacing(od) : iec_pvc_spacing(od)
      end
      return 3.0 unless type == 'PVC'

      # NEC / NTC Table 352.30 (PVC).
      case size
      when '1/2', '3/4', '1' then 0.9
      when '1-1/4', '1-1/2', '2' then 1.5
      when '2-1/2', '3' then 1.8
      else 2.1
      end
    end

    def iec_pvc_spacing(od)
      return 0.75 if od <= 16.5
      return 1.5 if od <= 25.5
      return 1.75 if od <= 40.5

      2.0
    end

    def iec_steel_spacing(od)
      return 0.75 if od <= 16.5
      return 1.75 if od <= 25.5
      return 2.0 if od <= 40.5

      2.25
    end

    # Support positions (distances from the start, m) along a supported
    # section of length `len` between two boxes/terminations.
    def strap_positions(len, spacing, end_off = STRAP_END_M)
      return [] if len <= 1.0e-6 || spacing <= 0

      return [len / 2.0] if len <= 2.0 * end_off

      first = end_off
      last = len - end_off
      span = last - first
      return [first] if span <= 1.0e-6

      gaps = [(span / spacing - 1.0e-9).ceil, 1].max
      (0..gaps).map { |i| first + span * i / gaps }
    end

    # ---- review ---------------------------------------------------------------

    # Code review of one run. `stats` keys: :type, :size, :max_deg, :max_len_m,
    # :fill (hash from #fill), :bend_radius_mm, :bend_mode.
    # Returns an Array of { level: :error|:warn|:info, msg: } in Spanish.
    def review(profile_key, stats)
      prof = profile(profile_key)
      out = []
      art = ARTICLE[stats[:type]]
      max_deg = (stats[:limit_deg] || prof[:max_bend_deg]).to_f
      if stats[:max_deg] && max_deg.positive? && stats[:max_deg] > max_deg + 0.5
        ref = if prof[:code] == 'IEC 60364'
                'referencia práctica IEC'
              else
                "#{prof[:code]} #{art ? "#{art}.26" : 'Cap. 3'}"
              end
        out << { level: :error,
                 msg: "Curvas entre cajas: #{stats[:max_deg].round}° > #{max_deg.round}° (#{ref}). " \
                      'Agrega una caja de paso.' }
      end
      max_len = prof[:max_len_m].to_f
      if max_len.positive? && stats[:max_len_m] && stats[:max_len_m] > max_len + 0.01
        out << { level: :warn,
                 msg: "Tramo sin registro de #{stats[:max_len_m].round(1)} m > #{max_len.round} m " \
                      '(referencia práctica IEC). Agrega una caja de paso.' }
      end
      f = stats[:fill]
      if f && f[:pct] && !f[:ok]
        sug = min_size(stats[:type], stats[:conds] || [])
        extra = sug ? " Usa #{Catalog.size_text(stats[:type], sug)} o mayor." : ''
        out << { level: :error,
                 msg: "Ocupación #{f[:pct]}% > #{f[:limit]}% con #{f[:count]} conductores " \
                      "(#{prof[:code] == 'IEC 60364' ? 'referencia' : prof[:code]} Cap. 9 Tabla 1).#{extra}" }
      end
      if stats[:bend_radius_mm] && stats[:bend_mode].to_s == 'field' && !Catalog.metric?(stats[:type])
        min = Catalog.min_bend_radius_mm(stats[:type], stats[:size])
        if stats[:bend_radius_mm] + 0.5 < min
          out << { level: :warn,
                   msg: "Radio de curvatura #{stats[:bend_radius_mm].round} mm < mínimo " \
                        "#{min.round} mm (Cap. 9 Tabla 2)." }
        end
      end
      out
    end

    def truthy(v)
      v == true || v == 'true' || v == 1 || v == '1'
    end
  end
end
