# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Catalog
  # ---------------------------------------------------------------------------
  # Central reference data for the plugin: raceway types, their sizes and
  # dimensions, fittings nomenclature and boxes. Pure data + helpers (no
  # SketchUp API) so it can be unit tested offline.
  #
  # Sources (documented for maintainers):
  #  * Outside diameters: EMT (ANSI C80.3 / UL 797), IMC (ANSI C80.6 /
  #    UL 1242), RMC (ANSI C80.1 / UL 6) and PVC Sch-40 (NEMA TC 2 / UL 651)
  #    trade tables, in millimetres.
  #  * Internal areas (100 %): NEC Chapter 9, Table 4 (identical in NTC 2050,
  #    Capítulo 9, Tabla 4).
  #  * Minimum bend radius to centreline: NEC Chapter 9, Table 2, column
  #    "One Shot and Full Shoe Benders" (the radius of a hand/one-shot bender),
  #    with the "Other Bends" column kept for reference.
  #  * Product standards: RETIE 2024 (Res. 40117), Art. 2.3.29 lists NTC 105
  #    (EMT), NTC 169 (IMC), NTC 171 (RMC), NTC 979 (PVC) and IEC 61386.
  #  * Metric rigid PVC (IEC 61386-21): OD = nominal size; internal diameters
  #    are typical medium-duty values (manufacturer data, approximate).
  # ===========================================================================
  module Catalog
    MM_PER_INCH = 25.4

    # Imperial trade sizes (NEC / NTC 2050 "tamaño comercial").
    TRADE_SIZES = %w[1/2 3/4 1 1-1/4 1-1/2 2 2-1/2 3 3-1/2 4].freeze

    # Metric designator per trade size (NEC Table 4 "Metric Designator").
    METRIC_DESIGNATOR = {
      '1/2' => 16, '3/4' => 21, '1' => 27, '1-1/4' => 35, '1-1/2' => 41,
      '2' => 53, '2-1/2' => 63, '3' => 78, '3-1/2' => 91, '4' => 103
    }.freeze

    # IEC 61386 metric conduit sizes (nominal outside diameter, mm).
    METRIC_SIZES = %w[16 20 25 32 40 50 63].freeze

    # Minimum bend radius to centreline (mm) — NEC Ch.9 Table 2,
    # "One Shot and Full Shoe Benders".
    MIN_BEND_RADIUS_MM = {
      '1/2' => 101.6, '3/4' => 114.3, '1' => 146.05, '1-1/4' => 184.15,
      '1-1/2' => 209.55, '2' => 241.3, '2-1/2' => 266.7, '3' => 330.2,
      '3-1/2' => 381.0, '4' => 406.4
    }.freeze

    # NEC Ch.9 Table 2, "Other Bends" (mm) — for reference / conservative use.
    OTHER_BEND_RADIUS_MM = {
      '1/2' => 101.6, '3/4' => 127.0, '1' => 152.4, '1-1/4' => 203.2,
      '1-1/2' => 254.0, '2' => 304.8, '2-1/2' => 381.0, '3' => 457.2,
      '3-1/2' => 533.4, '4' => 609.6
    }.freeze

    # Outside diameter (mm) per conduit type and size.
    OD_MM = {
      'EMT' => {
        '1/2' => 17.9, '3/4' => 23.4, '1' => 29.5, '1-1/4' => 38.4,
        '1-1/2' => 44.2, '2' => 55.8, '2-1/2' => 73.0, '3' => 88.9,
        '3-1/2' => 101.6, '4' => 114.3
      },
      'IMC' => {
        '1/2' => 20.7, '3/4' => 26.1, '1' => 32.8, '1-1/4' => 41.6,
        '1-1/2' => 47.8, '2' => 59.9, '2-1/2' => 72.6, '3' => 88.3,
        '3-1/2' => 100.9, '4' => 113.4
      },
      'GALV' => { # Rigid Metal Conduit — IPS outside diameters
        '1/2' => 21.3, '3/4' => 26.7, '1' => 33.4, '1-1/4' => 42.2,
        '1-1/2' => 48.3, '2' => 60.3, '2-1/2' => 73.0, '3' => 88.9,
        '3-1/2' => 101.6, '4' => 114.3
      },
      'PVC' => { # PVC Schedule 40 electrical — IPS outside diameters
        '1/2' => 21.3, '3/4' => 26.7, '1' => 33.4, '1-1/4' => 42.2,
        '1-1/2' => 48.3, '2' => 60.3, '2-1/2' => 73.0, '3' => 88.9,
        '3-1/2' => 101.6, '4' => 114.3
      },
      'PVCM' => {
        '16' => 16.0, '20' => 20.0, '25' => 25.0, '32' => 32.0,
        '40' => 40.0, '50' => 50.0, '63' => 63.0
      }
    }.freeze

    # Total internal area, 100 % (mm²) — NEC Ch.9 Table 4.
    AREA_MM2 = {
      'EMT' => { '1/2' => 196, '3/4' => 343, '1' => 556, '1-1/4' => 968, '1-1/2' => 1314,
                 '2' => 2165, '2-1/2' => 3783, '3' => 5701, '3-1/2' => 7451, '4' => 9521 },
      'IMC' => { '1/2' => 222, '3/4' => 377, '1' => 620, '1-1/4' => 1064, '1-1/2' => 1432,
                 '2' => 2341, '2-1/2' => 3308, '3' => 5115, '3-1/2' => 6822, '4' => 8725 },
      'GALV' => { '1/2' => 204, '3/4' => 353, '1' => 573, '1-1/4' => 984, '1-1/2' => 1333,
                  '2' => 2198, '2-1/2' => 3137, '3' => 4840, '3-1/2' => 6461, '4' => 8316 },
      'PVC' => { '1/2' => 184, '3/4' => 327, '1' => 535, '1-1/4' => 935, '1-1/2' => 1282,
                 '2' => 2124, '2-1/2' => 3029, '3' => 4693, '3-1/2' => 6277, '4' => 8091 },
      # π/4·ID² with typical medium-duty IDs 13.4/16.9/21.4/27.8/35.4/44.3/56.5 mm.
      'PVCM' => { '16' => 141, '20' => 224, '25' => 360, '32' => 607, '40' => 984,
                  '50' => 1541, '63' => 2507 }
    }.freeze

    # Per-conduit-type descriptors.
    #  :label       -> human name
    #  :short       -> short name for the UI
    #  :connection  -> :setscrew | :compression | :threaded | :solvent
    #  :color       -> RGB used for the modeled material
    #  :stock_m     -> default commercial stock length in metres
    #  :std         -> product standards (RETIE 2024 Art. 2.3.29 / UL / IEC)
    #  :nec         -> NEC / NTC 2050 article
    #  :metric      -> sizes are IEC metric (mm) instead of trade sizes
    TYPES = {
      'EMT' => {
        label: 'EMT — Tubo conduit metálico pared delgada',
        short: 'EMT', connection: :setscrew, color: [176, 179, 184],
        stock_m: 3.0, std: 'NTC 105 / UL 797', nec: '358'
      },
      'IMC' => {
        label: 'IMC — Conduit metálico intermedio (roscado)',
        short: 'IMC', connection: :threaded, color: [150, 152, 158],
        stock_m: 3.0, std: 'NTC 169 / UL 1242', nec: '342'
      },
      'GALV' => {
        label: 'RMC — Conduit galvanizado pared gruesa (roscado)',
        short: 'RMC', connection: :threaded, color: [130, 132, 138],
        stock_m: 3.0, std: 'NTC 171 / UL 6', nec: '344'
      },
      'PVC' => {
        label: 'PVC conduit Sch-40 (cementado)',
        short: 'PVC', connection: :solvent, color: [70, 74, 82],
        stock_m: 3.0, std: 'NTC 979 / UL 651', nec: '352'
      },
      'PVCM' => {
        label: 'PVC rígido métrico — IEC 61386-21',
        short: 'PVC-IEC', connection: :solvent, color: [205, 207, 210],
        stock_m: 3.0, std: 'IEC 61386-21', nec: nil, metric: true
      }
    }.freeze

    TYPE_KEYS = TYPES.keys.freeze

    # -----------------------------------------------------------------------
    # Connection / coupling nomenclature per type. Used to name BOM parts.
    # -----------------------------------------------------------------------
    COUPLING_NAME = {
      setscrew:    'Unión set-screw (tornillo)',
      compression: 'Unión a compresión',
      threaded:    'Unión roscada',
      solvent:     'Unión para cementar'
    }.freeze

    CONNECTOR_NAME = {
      setscrew:    'Conector set-screw a caja',
      compression: 'Conector a compresión a caja',
      threaded:    'Contratuerca',
      solvent:     'Adaptador terminal + contratuerca'
    }.freeze

    BUSHING_STD = 'Boquilla (bushing) aislante'
    BUSHING_GND = 'Boquilla (bushing) de puesta a tierra'
    LOCKNUT     = 'Contratuerca (locknut)'
    ELBOW_NAME  = 'Codo prefabricado'
    STRAP_NAME  = 'Abrazadera / grapa de 1 ala'

    # Standard factory elbow angles (degrees).
    STD_ELBOWS = [90.0, 45.0, 30.0, 22.5].freeze

    # -----------------------------------------------------------------------
    # Boxes. Sizes in mm as {w, h, d}; w is the long axis (condulets align it
    # with the conduit run).
    # -----------------------------------------------------------------------
    STEEL = [176, 179, 184].freeze
    BOXES = {
      # --- Standard galvanised steel boxes (embedded or surface) ---
      'STD_2X4'   => { family: 'Estándar', label: 'Caja rectangular 2×4"', w: 101, h: 55, d: 47,
                       color: STEEL, std: 'UL 514A' },
      'STD_4X4'   => { family: 'Estándar', label: 'Caja cuadrada 4×4"', w: 101, h: 101, d: 55,
                       color: STEEL, std: 'UL 514A' },
      'STD_5X5'   => { family: 'Estándar', label: 'Caja cuadrada 5×5"', w: 127, h: 127, d: 55,
                       color: STEEL, std: 'UL 514A' },
      'STD_OCT'   => { family: 'Estándar', label: 'Caja octagonal 4"', w: 101, h: 101, d: 47,
                       color: STEEL, std: 'UL 514A' },

      # --- Plexo (Legrand) plastic watertight ---
      'PLEXO_80'  => { family: 'Plexo', label: 'Caja Plexo 80×80×45 IP55', w: 80, h: 80, d: 45,
                       color: [225, 227, 230], std: 'IEC 60670-1' },
      'PLEXO_105' => { family: 'Plexo', label: 'Caja Plexo 105×105×55 IP55', w: 105, h: 105, d: 55,
                       color: [225, 227, 230], std: 'IEC 60670-1' },
      'PLEXO_155' => { family: 'Plexo', label: 'Caja Plexo 155×110×70 IP55', w: 155, h: 110, d: 70,
                       color: [225, 227, 230], std: 'IEC 60670-1' },
      'PLEXO_220' => { family: 'Plexo', label: 'Caja Plexo 220×170×80 IP55', w: 220, h: 170, d: 80,
                       color: [225, 227, 230], std: 'IEC 60670-1' },
      'PLEXO_310' => { family: 'Plexo', label: 'Caja Plexo 310×240×125 IP55', w: 310, h: 240, d: 125,
                       color: [225, 227, 230], std: 'IEC 60670-1' },

      # --- Rawelt cast condulets (conduit bodies) and FS/FD boxes ---
      'RAWELT_C'  => { family: 'Rawelt', label: 'Conduleta Rawelt tipo C', w: 90, h: 45, d: 45,
                       color: [180, 182, 186], condulet: :C, std: 'UL 514B' },
      'RAWELT_LB' => { family: 'Rawelt', label: 'Conduleta Rawelt tipo LB', w: 90, h: 60, d: 55,
                       color: [180, 182, 186], condulet: :LB, std: 'UL 514B' },
      'RAWELT_LL' => { family: 'Rawelt', label: 'Conduleta Rawelt tipo LL', w: 90, h: 60, d: 55,
                       color: [180, 182, 186], condulet: :LL, std: 'UL 514B' },
      'RAWELT_LR' => { family: 'Rawelt', label: 'Conduleta Rawelt tipo LR', w: 90, h: 60, d: 55,
                       color: [180, 182, 186], condulet: :LR, std: 'UL 514B' },
      'RAWELT_T'  => { family: 'Rawelt', label: 'Conduleta Rawelt tipo T', w: 95, h: 90, d: 55,
                       color: [180, 182, 186], condulet: :T, std: 'UL 514B' },
      'RAWELT_X'  => { family: 'Rawelt', label: 'Conduleta Rawelt tipo X (cruz)', w: 95, h: 95, d: 55,
                       color: [180, 182, 186], condulet: :X, std: 'UL 514B' },
      'RAWELT_FS' => { family: 'Rawelt', label: 'Caja Rawelt FS (1 tapa)', w: 100, h: 70, d: 55,
                       color: [180, 182, 186], std: 'UL 514A' },
      'RAWELT_FD' => { family: 'Rawelt', label: 'Caja Rawelt FD (fondo profundo)', w: 100, h: 70, d: 75,
                       color: [180, 182, 186], std: 'UL 514A' }
    }.freeze

    BOX_KEYS = BOXES.keys.freeze
    DEFAULT_BOX = 'STD_4X4'

    module_function

    # ---- helpers ----------------------------------------------------------

    def type_info(type)
      TYPES[type] || TYPES['EMT']
    end

    def metric?(type)
      type_info(type)[:metric] ? true : false
    end

    # Sizes available for a raceway type.
    def sizes_for(type)
      metric?(type) ? METRIC_SIZES : TRADE_SIZES
    end

    def default_size(type)
      metric?(type) ? '20' : '3/4'
    end

    # Outside diameter (mm) for a type/size, falling back gracefully.
    def od_mm(type, size)
      t = OD_MM[type] || OD_MM['EMT']
      t[size] || OD_MM['EMT'][size] || 20.0
    end

    # Internal area (mm², 100 %) for a type/size, or nil if unknown.
    def area_mm2(type, size)
      (AREA_MM2[type] || {})[size]
    end

    # Minimum bend radius (mm). For metric PVC (no code table) a
    # manufacturer-style 4×OD is used.
    def min_bend_radius_mm(type, size = nil)
      # Backwards compatible single-argument form: min_bend_radius_mm(size).
      if size.nil?
        size = type
        type = 'EMT'
      end
      return (od_mm(type, size) * 4.0).round(1) if metric?(type)

      MIN_BEND_RADIUS_MM[size] || 150.0
    end

    def connection_method(type)
      type_info(type)[:connection]
    end

    def coupling_label(type)
      COUPLING_NAME[connection_method(type)]
    end

    def connector_label(type)
      CONNECTOR_NAME[connection_method(type)]
    end

    # A short human label like "EMT 3/4\"" or "PVC-IEC Ø20 mm".
    def size_label(type, size)
      info = type_info(type)
      metric?(type) ? "#{info[:short]} Ø#{size} mm" : %(#{info[:short]} #{size}")
    end

    # Size only, e.g. '3/4"' or 'Ø20 mm'.
    def size_text(type, size)
      metric?(type) ? "Ø#{size} mm" : %(#{size}")
    end

    def valid_type?(type)
      TYPES.key?(type)
    end

    def valid_size?(size, type = nil)
      type ? sizes_for(type).include?(size) : (TRADE_SIZES + METRIC_SIZES).include?(size)
    end

    # Nearest standard factory elbow for a deflection (degrees). Returns
    # [nominal_deg, exact?] — exact when within 3° of a standard angle.
    def standard_elbow(deg)
      best = STD_ELBOWS.min_by { |a| (a - deg).abs }
      [best, (best - deg).abs <= 3.0]
    end
  end
end
