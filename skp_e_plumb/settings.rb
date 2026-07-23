# frozen_string_literal: true

module SkpEPlumb
  # ===========================================================================
  # Settings
  # ---------------------------------------------------------------------------
  # Current drawing settings, persisted between sessions with Sketchup
  # read_default / write_default. The active ConduitTool reads these live, so
  # changing a value in the dialog affects the very next click.
  # ===========================================================================
  module Settings
    SECTION = 'SkpEPlumb'

    DEFAULTS = {
      'type'           => 'EMT',
      'size'           => '3/4',
      'stock_m'        => 3.0,
      'bend_radius_mm' => 114.3,   # NEC min for 3/4"
      'bend_mode'      => 'field', # 'field' | 'premade'
      'connection'     => 'setscrew', # only meaningful for EMT
      'termination'    => 'std',   # 'none' | 'std' | 'gnd'
      'box_key'        => 'PLEXO_105',
      'segments'       => 24,
      'auto_box'       => false,   # RETIE: drop a box after every N curves
      'auto_box_every' => 2,
      'bom_mode'       => 'pieces', # 'pieces' | 'optimized'
      'surface_mount'  => false    # offset the tube out of the surface it's on
    }.freeze

    @state = nil

    module_function

    def load!
      @state = {}
      DEFAULTS.each do |k, default|
        @state[k] = Sketchup.read_default(SECTION, k, default)
      end
      # Keep the bend radius sane for the current size on first load.
      @state
    end

    def state
      load! if @state.nil?
      @state
    end

    def get(key)
      state[key]
    end

    def set(key, value)
      state[key] = value
      Sketchup.write_default(SECTION, key, value)
      value
    end

    # Convenience typed getters -------------------------------------------
    def type
      state['type']
    end

    def size
      state['size']
    end

    def stock_m
      state['stock_m'].to_f
    end

    def bend_radius_mm
      state['bend_radius_mm'].to_f
    end

    def bend_mode
      state['bend_mode'].to_sym
    end

    def connection
      state['connection'].to_sym
    end

    def termination
      state['termination'].to_sym
    end

    def box_key
      state['box_key']
    end

    def segments
      state['segments'].to_i
    end

    def auto_box?
      v = state['auto_box']
      v == true || v == 'true' || v == 1
    end

    def auto_box_every
      e = state['auto_box_every'].to_i
      e < 1 ? 2 : e
    end

    def surface_mount?
      v = state['surface_mount']
      v == true || v == 'true' || v == 1
    end

    def field_bend?
      bend_mode == :field
    end

    def toggle_bend_mode!
      new_mode = field_bend? ? 'premade' : 'field'
      set('bend_mode', new_mode)
      new_mode.to_sym
    end

    # When the user picks a new size, snap the bend radius to the NEC minimum
    # unless they had deliberately set something larger.
    def apply_size!(new_size)
      set('size', new_size)
      set('bend_radius_mm', Catalog.min_bend_radius_mm(new_size))
    end

    # A compact hash used to render dialogs.
    def snapshot
      {
        'type' => type, 'size' => size, 'stock_m' => stock_m,
        'bend_radius_mm' => bend_radius_mm, 'bend_mode' => bend_mode.to_s,
        'connection' => connection.to_s, 'termination' => termination.to_s,
        'box_key' => box_key, 'segments' => segments
      }
    end
  end
end
