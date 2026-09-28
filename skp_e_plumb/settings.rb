# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Settings
  # ---------------------------------------------------------------------------
  # Current drawing settings, persisted between sessions with Sketchup
  # read_default / write_default. The active tools read these live, so
  # changing a value in the panel affects the very next click.
  # ===========================================================================
  module Settings
    SECTION = 'SkpEPlumb'

    DEFAULTS = {
      'profile'        => 'NTC',      # 'NTC' | 'NEC' | 'IEC'
      'type'           => 'EMT',
      'size'           => '3/4',
      'install'        => 'surface',  # 'surface' (a la vista) | 'embedded' (empotrado)
      'stock_m'        => 3.0,
      'bend_radius_mm' => 114.3,
      'bend_mode'      => 'field',    # 'field' | 'premade'
      'connection'     => 'setscrew', # only meaningful for EMT
      'termination'    => 'std',      # 'none' | 'std' | 'gnd'
      'box_key'        => Catalog::DEFAULT_BOX,
      'pull_boxes'     => false,      # insert pull boxes when bends exceed the limit
      'max_bend_deg'   => 360,
      'straps'         => true,       # model supports (surface install)
      'standoff_mm'    => 0.0,        # extra gap between tube and surface
      'cover_mm'       => 5.0,        # plaster cover over embedded tube
      'segments'       => 16,
      'bom_mode'       => 'pieces',   # 'pieces' | 'optimized'
      # Wiring (conductors inside the conduit) -------------------------------
      'circuits'       => 1,          # 0 = no conductors
      'circuit'        => '1F+N',
      'system'         => '240',
      'wire_size'      => '12',
      'ground'         => true,
      'ground_size'    => 'same',
      'insulation'     => 'THHN',
      'check_updates'  => true
    }.freeze

    BOOL_KEYS = %w[pull_boxes straps ground check_updates].freeze
    FLOAT_KEYS = %w[stock_m bend_radius_mm standoff_mm cover_mm].freeze
    INT_KEYS = %w[segments max_bend_deg circuits].freeze

    @state = nil

    module_function

    def load!
      @state = {}
      DEFAULTS.each do |k, default|
        @state[k] = Sketchup.read_default(SECTION, k, default)
      end
      migrate!
      sanitize!
      @state
    end

    # Carry over settings from 1.x so an update does not lose the user's setup.
    def migrate!
      return if Sketchup.read_default(SECTION, 'migrated_v2', false)

      old_surface = Sketchup.read_default(SECTION, 'surface_mount', nil)
      set('install', 'surface') unless old_surface.nil?
      old_auto = Sketchup.read_default(SECTION, 'auto_box', nil)
      unless old_auto.nil?
        set('pull_boxes', truthy(old_auto))
        every = Sketchup.read_default(SECTION, 'auto_box_every', 2).to_i
        set('max_bend_deg', [[every, 1].max * 90, 360].min) if truthy(old_auto)
      end
      Sketchup.write_default(SECTION, 'migrated_v2', true)
    rescue StandardError
      nil
    end

    # Keep values consistent (a size valid for the type, known keys, ...).
    def sanitize!
      @state['profile'] = 'NTC' unless Codes::PROFILES.key?(@state['profile'])
      @state['type'] = 'EMT' unless Catalog.valid_type?(@state['type'])
      @state['size'] = Catalog.default_size(type) unless Catalog.valid_size?(@state['size'], type)
      @state['box_key'] = Catalog::DEFAULT_BOX unless Catalog::BOXES.key?(@state['box_key'])
      @state['install'] = 'surface' unless %w[surface embedded].include?(@state['install'])
      @state['insulation'] = Codes.profile(profile)[:insulation] unless Codes::INSULATION.key?(@state['insulation'])
      units = Codes.insulation(@state['insulation'])[:units]
      sizes = Codes.sizes_for_units(units)
      @state['wire_size'] = sizes[1] unless sizes.include?(@state['wire_size'].to_s)
      unless @state['ground_size'] == 'same' || sizes.include?(@state['ground_size'].to_s)
        @state['ground_size'] = 'same'
      end
      @state['circuit'] = '1F+N' unless Codes::CIRCUITS.key?(@state['circuit'])
      @state['system'] = '240' unless Codes::SYSTEMS.key?(@state['system'].to_s)
      @state['system'] = @state['system'].to_s
    end

    def state
      load! if @state.nil?
      @state
    end

    def get(key)
      state[key]
    end

    def set(key, value)
      state[key] = coerce(key, value)
      Sketchup.write_default(SECTION, key, state[key])
      state[key]
    end

    def coerce(key, value)
      if BOOL_KEYS.include?(key) then truthy(value)
      elsif FLOAT_KEYS.include?(key) then value.to_f
      elsif INT_KEYS.include?(key) then value.to_i
      else value.to_s
      end
    end

    def truthy(v)
      v == true || v == 'true' || v == 1 || v == '1'
    end

    # Convenience typed getters -------------------------------------------
    def profile
      state['profile']
    end

    def type
      state['type']
    end

    def size
      state['size']
    end

    def stock_m
      v = state['stock_m'].to_f
      v < 0.3 ? 3.0 : v
    end

    def bend_radius_mm
      state['bend_radius_mm'].to_f
    end

    def bend_mode
      state['bend_mode'].to_s == 'premade' ? :premade : :field
    end

    def connection
      state['connection'].to_s == 'compression' ? :compression : :setscrew
    end

    def termination
      t = state['termination'].to_s
      %w[none std gnd].include?(t) ? t.to_sym : :std
    end

    def box_key
      state['box_key']
    end

    def segments
      [[state['segments'].to_i, 8].max, 48].min
    end

    def surface?
      state['install'] != 'embedded'
    end

    def pull_boxes?
      truthy(state['pull_boxes'])
    end

    def max_bend_deg
      v = state['max_bend_deg'].to_i
      v < 90 ? 360 : v
    end

    def straps?
      truthy(state['straps'])
    end

    def check_updates?
      truthy(state['check_updates'])
    end

    def field_bend?
      bend_mode == :field
    end

    def toggle_bend_mode!
      new_mode = field_bend? ? 'premade' : 'field'
      set('bend_mode', new_mode)
      new_mode.to_sym
    end

    # A new type may use another size system (trade vs metric): keep the size
    # if valid, otherwise pick the type's default, and refresh the radius.
    def apply_type!(new_type)
      set('type', new_type)
      set('size', Catalog.default_size(new_type)) unless Catalog.valid_size?(size, new_type)
      set('bend_radius_mm', Catalog.min_bend_radius_mm(new_type, size))
    end

    # A new size snaps the bend radius to the code minimum for that size.
    def apply_size!(new_size)
      set('size', new_size)
      set('bend_radius_mm', Catalog.min_bend_radius_mm(type, new_size))
    end

    # A new profile brings its defaults (bend limit, conductor insulation and
    # units); type/size are left alone unless the profile implies metric.
    def apply_profile!(key)
      set('profile', key)
      prof = Codes.profile(key)
      set('max_bend_deg', prof[:max_bend_deg])
      set('insulation', prof[:insulation])
      sizes = Codes.sizes_for_units(Codes.insulation(prof[:insulation])[:units])
      set('wire_size', sizes[1]) unless sizes.include?(state['wire_size'].to_s)
      set('ground_size', 'same')
    end

    # Wiring spec as consumed by Codes.conductors.
    def wiring_spec
      {
        'circuits' => state['circuits'].to_i, 'circuit' => state['circuit'],
        'system' => state['system'], 'wire_size' => state['wire_size'].to_s,
        'ground' => truthy(state['ground']), 'ground_size' => state['ground_size'].to_s,
        'insulation' => state['insulation'], 'profile' => profile
      }
    end

    # Options hash handed to Builder.build_run for a new run.
    def run_options
      {
        profile: profile, type: type, size: size, stock_m: stock_m,
        bend_radius_mm: bend_radius_mm, bend_mode: bend_mode,
        termination: termination.to_s, connection: connection, segments: segments,
        terminate_start: termination != :none, terminate_end: termination != :none,
        pull_boxes: pull_boxes?, max_bend_deg: max_bend_deg, box_key: box_key,
        install: surface? ? 'surface' : 'embedded', straps: straps?,
        standoff_mm: state['standoff_mm'].to_f, cover_mm: state['cover_mm'].to_f,
        wiring: wiring_spec
      }
    end
  end
end
