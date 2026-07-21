# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Catalog
  # ---------------------------------------------------------------------------
  # Central reference data for the plugin. Everything the modeler and the BOM
  # need to know about real electrical raceways lives here so it can be edited
  # in a single place.
  #
  # Sources / rationale (documented for maintainers):
  #  * Outside diameters (OD) follow the usual trade tables. EMT is thin wall;
  #    IMC is intermediate wall; Galvanized (RMC) and PVC Sch-40 follow IPS
  #    (iron-pipe-size) outside diameters. Values are in millimetres.
  #  * Minimum bend radii follow NEC Chapter 9, Table 2, column "Other Bends"
  #    (radius to the centreline of the conduit). They are the default radius
  #    proposed for both field bends and factory sweeps; the user may override.
  #  * Connection methods reflect real practice:
  #      - EMT  -> set-screw / compression fittings (NOT threaded).
  #      - IMC  -> threaded couplings; terminates with locknut + bushing.
  #      - GALV -> threaded couplings; terminates with locknut + bushing.
  #      - PVC  -> solvent-welded (cemented) slip fittings; terminal adapter.
  # ===========================================================================
  module Catalog
    MM_PER_INCH = 25.4

    # Ordered list of trade sizes we support (imperial designation + metric
    # "designator" used in IEC/metric catalogs).
    TRADE_SIZES = %w[1/2 3/4 1 1-1/4 1-1/2 2 2-1/2 3 3-1/2 4].freeze

    # Metric designator per trade size (mm) — informational, shown in the UI.
    METRIC_DESIGNATOR = {
      '1/2' => 16, '3/4' => 21, '1' => 27, '1-1/4' => 35, '1-1/2' => 41,
      '2' => 53, '2-1/2' => 63, '3' => 78, '3-1/2' => 91, '4' => 103
    }.freeze

    # Minimum bend radius to centreline (mm) — NEC Ch.9 Table 2 "Other Bends".
    MIN_BEND_RADIUS_MM = {
      '1/2' => 101.6, '3/4' => 114.3, '1' => 146.05, '1-1/4' => 184.15,
      '1-1/2' => 209.55, '2' => 241.3, '2-1/2' => 266.7, '3' => 330.2,
      '3-1/2' => 381.0, '4' => 406.4
    }.freeze

    # Outside diameter (mm) per conduit type and trade size.
    OD_MM = {
      'EMT' => {
        '1/2' => 17.9, '3/4' => 23.4, '1' => 29.5, '1-1/4' => 38.4,
        '1-1/2' => 44.2, '2' => 55.8, '2-1/2' => 73.0, '3' => 88.9,
        '3-1/2' => 101.6, '4' => 114.3
      },
      'IMC' => {
        '1/2' => 19.8, '3/4' => 25.3, '1' => 31.8, '1-1/4' => 40.6,
        '1-1/2' => 46.7, '2' => 58.4, '2-1/2' => 71.9, '3' => 87.4,
        '3-1/2' => 100.1, '4' => 112.6
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
      }
    }.freeze

    # Per-conduit-type descriptors.
    #  :label       -> human name (bilingual EN / ES)
    #  :connection  -> :setscrew | :compression | :threaded | :solvent
    #  :bendable    -> can it be field-bent with a bender?
    #  :color       -> RGB used for the modeled material
    #  :stock_m     -> default commercial stock length in metres
    #  :termination -> how the raceway terminates into boxes/panels
    TYPES = {
      'EMT' => {
        label: 'EMT — Tubo conduit pared delgada',
        connection: :setscrew,
        bendable: true,
        color: [176, 179, 184], # galvanized steel grey
        stock_m: 3.0,
        termination: :connector # set-screw/compression connector (insulated throat option)
      },
      'IMC' => {
        label: 'IMC — Tubo conduit pared intermedia (roscado)',
        connection: :threaded,
        bendable: true,
        color: [150, 152, 158],
        stock_m: 3.0,
        termination: :locknut_bushing
      },
      'GALV' => {
        label: 'Galvanizado / RMC — Pared gruesa (roscado)',
        connection: :threaded,
        bendable: true,
        color: [130, 132, 138],
        stock_m: 3.0,
        termination: :locknut_bushing
      },
      'PVC' => {
        label: 'PVC eléctrico Sch-40 (cementado)',
        connection: :solvent,
        bendable: false, # cold-bent only with heat; treated as premade elbows
        color: [40, 44, 52], # conduit grey/black
        stock_m: 3.0,
        termination: :terminal_adapter
      }
    }.freeze

    TYPE_KEYS = TYPES.keys.freeze

    # -----------------------------------------------------------------------
    # Connection / coupling nomenclature per type. Used to name BOM parts.
    # -----------------------------------------------------------------------
    COUPLING_NAME = {
      setscrew:    'Copla set-screw (tornillo)',
      compression: 'Copla a compresión',
      threaded:    'Copla roscada',
      solvent:     'Copla cementar (PVC)'
    }.freeze

    CONNECTOR_NAME = {
      setscrew:        'Conector set-screw a caja',
      compression:     'Conector a compresión a caja',
      threaded:        'Contratuerca + bushing a caja',
      solvent:         'Adaptador terminal (macho) + contratuerca'
    }.freeze

    # -----------------------------------------------------------------------
    # Accessories that always exist as their own BOM lines.
    # -----------------------------------------------------------------------
    BUSHING_STD  = 'Bushing / anillo aislante'
    BUSHING_GND  = 'Bushing de aterrizaje (grounding)'
    LOCKNUT      = 'Contratuerca (locknut)'
    ELBOW_90     = 'Codo 90° prefabricado'
    ELBOW_45     = 'Codo 45° prefabricado'

    # -----------------------------------------------------------------------
    # Boxes. Two families requested by the field:
    #   * Plexo (Legrand): watertight IP55 plastic boxes for exposed/PVC work.
    #   * Rawelt: cast condulets (conduit bodies) and FS/FD boxes for metallic
    #     conduit (EMT / IMC / RMC).
    # Sizes in mm as {w, h, d}. :entries is a hint for typical hub count.
    # -----------------------------------------------------------------------
    BOXES = {
      # --- Plexo (Legrand) plastic watertight ---
      'PLEXO_80'   => { family: 'Plexo', label: 'Caja Plexo 80×80×45 IP55',
                        w: 80, h: 80, d: 45, color: [225, 227, 230] },
      'PLEXO_105'  => { family: 'Plexo', label: 'Caja Plexo 105×105×55 IP55',
                        w: 105, h: 105, d: 55, color: [225, 227, 230] },
      'PLEXO_155'  => { family: 'Plexo', label: 'Caja Plexo 155×110×70 IP55',
                        w: 155, h: 110, d: 70, color: [225, 227, 230] },
      'PLEXO_220'  => { family: 'Plexo', label: 'Caja Plexo 220×170×80 IP55',
                        w: 220, h: 170, d: 80, color: [225, 227, 230] },
      'PLEXO_310'  => { family: 'Plexo', label: 'Caja Plexo 310×240×125 IP55',
                        w: 310, h: 240, d: 125, color: [225, 227, 230] },

      # --- Rawelt cast condulets (conduit bodies) ---
      'RAWELT_C'   => { family: 'Rawelt', label: 'Condulet Rawelt tipo C',
                        w: 90, h: 45, d: 45, color: [180, 182, 186], condulet: :C },
      'RAWELT_LB'  => { family: 'Rawelt', label: 'Condulet Rawelt tipo LB',
                        w: 90, h: 60, d: 55, color: [180, 182, 186], condulet: :LB },
      'RAWELT_LL'  => { family: 'Rawelt', label: 'Condulet Rawelt tipo LL',
                        w: 90, h: 60, d: 55, color: [180, 182, 186], condulet: :LL },
      'RAWELT_LR'  => { family: 'Rawelt', label: 'Condulet Rawelt tipo LR',
                        w: 90, h: 60, d: 55, color: [180, 182, 186], condulet: :LR },
      'RAWELT_T'   => { family: 'Rawelt', label: 'Condulet Rawelt tipo T',
                        w: 95, h: 90, d: 55, color: [180, 182, 186], condulet: :T },
      'RAWELT_X'   => { family: 'Rawelt', label: 'Condulet Rawelt tipo X (cruz)',
                        w: 95, h: 95, d: 55, color: [180, 182, 186], condulet: :X },
      'RAWELT_FS'  => { family: 'Rawelt', label: 'Caja Rawelt FS (1 tapa)',
                        w: 70, h: 100, d: 55, color: [180, 182, 186] },
      'RAWELT_FD'  => { family: 'Rawelt', label: 'Caja Rawelt FD (fondo profundo)',
                        w: 70, h: 100, d: 75, color: [180, 182, 186] }
    }.freeze

    BOX_KEYS = BOXES.keys.freeze

    module_function

    # ---- helpers ----------------------------------------------------------

    # Outside diameter (mm) for a type/size, falling back gracefully.
    def od_mm(type, size)
      (OD_MM[type] && OD_MM[type][size]) || OD_MM['EMT'][size] || 20.0
    end

    def min_bend_radius_mm(size)
      MIN_BEND_RADIUS_MM[size] || 150.0
    end

    def type_info(type)
      TYPES[type] || TYPES['EMT']
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

    # A short human label like "EMT 3/4\"".
    def size_label(type, size)
      %(#{type} #{size}")
    end

    def valid_type?(type)
      TYPES.key?(type)
    end

    def valid_size?(size)
      TRADE_SIZES.include?(size)
    end
  end
end
