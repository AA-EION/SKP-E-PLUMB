# frozen_string_literal: true

require 'sketchup.rb'

begin
  require 'json'
rescue LoadError
  # JSON is optional; UIDialogs has a manual fallback encoder.
end

module SkpEPlumb
  # Load order matters: data -> geometry -> bom -> settings -> builder -> tools
  # -> ui -> menus. Any failure here is surfaced so it is never silent.
  dir = __dir__
  begin
    %w[
      version catalog geom_util bom settings builder cursors
      conduit_tool box_tool edit_tool ui_dialogs
    ].each { |f| require File.join(dir, "#{f}.rb") }
  rescue StandardError => e
    UI.messagebox("SKP E-Plumb no pudo cargar:\n\n#{e.class}: #{e.message}\n\n" \
                  "#{(e.backtrace || [])[0, 6].join("\n")}")
    raise
  end

  # ===========================================================================
  # Menu / toolbar wiring
  # ===========================================================================
  module Menus
    module_function

    ICONS = File.join(__dir__, 'resources', 'icons').freeze

    # Run a command body, turning any exception into a visible message box so a
    # failure is reportable instead of a silent no-op.
    def safe(context)
      yield
    rescue StandardError => e
      trace = (e.backtrace || [])[0, 6].join("\n")
      UI.messagebox("SKP E-Plumb — error en #{context}:\n\n#{e.class}: #{e.message}\n\n#{trace}")
    end

    def apply_icon(cmd, base)
      small = File.join(ICONS, "#{base}_16.png")
      large = File.join(ICONS, "#{base}_24.png")
      cmd.small_icon = small if File.exist?(small)
      cmd.large_icon = large if File.exist?(large)
    end

    def cmd_draw
      c = UI::Command.new('Dibujar tubería') do
        safe('Dibujar tubería') { Sketchup.active_model.select_tool(ConduitTool.new) }
      end
      c.tooltip = 'Dibujar tubería / canalización eléctrica'
      c.status_bar_text = 'Clic para marcar el trazado. Alt/Option cambia entre doblar tubo y codo prefabricado.'
      apply_icon(c, 'conduit')
      c
    end

    def cmd_edit
      c = UI::Command.new('Editar tubería') do
        safe('Editar tubería') { Sketchup.active_model.select_tool(EditTool.new) }
      end
      c.tooltip = 'Editar por anclas una tubería existente'
      c.status_bar_text = 'Clic en una tubería; arrastra anclas, inserta/borra vértices, extiende y aplica con Enter.'
      apply_icon(c, 'edit')
      c
    end

    def cmd_box
      c = UI::Command.new('Colocar caja') do
        safe('Colocar caja') { Sketchup.active_model.select_tool(BoxTool.new) }
      end
      c.tooltip = 'Colocar caja (Plexo / Rawelt)'
      c.status_bar_text = 'Clic para ubicar la caja seleccionada en Ajustes.'
      apply_icon(c, 'box')
      c
    end

    def cmd_toggle
      c = UI::Command.new('Cambiar modo de curva') do
        safe('Cambiar modo de curva') do
          mode = Settings.toggle_bend_mode!
          UIDialogs.refresh_settings
          Sketchup.set_status_text("Modo de curva: #{mode == :field ? 'DOBLAR TUBO' : 'CODO PREFABRICADO'}")
        end
      end
      c.tooltip = 'Alternar doblar tubo / codo prefabricado'
      c.status_bar_text = 'Cambia cómo se resuelven las curvas al dibujar.'
      apply_icon(c, 'bend')
      c
    end

    def cmd_bom
      c = UI::Command.new('Ver BOM') { safe('Ver BOM') { UIDialogs.show_bom } }
      c.tooltip = 'Ver lista de materiales (BOM)'
      c.status_bar_text = 'Genera y muestra la lista de materiales del modelo.'
      apply_icon(c, 'bom')
      c
    end

    def cmd_export_csv
      c = UI::Command.new('Exportar BOM (CSV)') { safe('Exportar CSV') { UIDialogs.export_bom(:csv) } }
      c.tooltip = 'Exportar BOM a CSV'
      c
    end

    def cmd_export_html
      c = UI::Command.new('Exportar BOM (HTML)') { safe('Exportar HTML') { UIDialogs.export_bom(:html) } }
      c.tooltip = 'Exportar BOM a HTML'
      c
    end

    def cmd_settings
      c = UI::Command.new('Ajustes…') { safe('Ajustes') { UIDialogs.show_settings } }
      c.tooltip = 'Ajustes de SKP E-Plumb'
      c.status_bar_text = 'Tipo de canalización, diámetro, tramo de stock, radio de curvatura, cajas.'
      apply_icon(c, 'settings')
      c
    end

    def cmd_diagnostics
      UI::Command.new('Diagnóstico…') do
        safe('Diagnóstico') do
          info = [
            "SKP E-Plumb v#{SkpEPlumb::VERSION}",
            "Ruby: #{RUBY_VERSION}",
            "SketchUp: #{Sketchup.version}",
            "HtmlDialog: #{defined?(UI::HtmlDialog) ? 'disponible' : 'NO disponible'}",
            "Módulos: Catalog=#{defined?(Catalog) ? 'ok' : '-'}, " \
              "Builder=#{defined?(Builder) ? 'ok' : '-'}, " \
              "UIDialogs=#{defined?(UIDialogs) ? 'ok' : '-'}",
            '',
            'Se abrirá el diálogo de Ajustes para comprobar la UI.'
          ]
          UI.messagebox(info.join("\n"))
          UIDialogs.show_settings
        end
      end
    end

    def cmd_about
      UI::Command.new('Acerca de…') { show_about }
    end

    def show_about
      msg = <<~TXT
        SKP E-Plumb v#{SkpEPlumb::VERSION}
        Modelador de canalizaciones eléctricas y BOM para SketchUp.

        Soporta EMT, IMC, Galvanizado (RMC) y PVC eléctrico con coplas,
        codos, curvas de campo, bushings, contratuercas y cajas
        (Plexo / Rawelt), respetando el tramo comercial del inventario.
        Las tuberías se pueden editar por anclas (herramienta Editar).

        Licencia GPL-3.0-or-later · © 2026 AA-EION
      TXT
      UI.messagebox(msg)
    end

    def build
      menu = UI.menu('Extensions').add_submenu('SKP E-Plumb')
      menu.add_item(cmd_draw)
      menu.add_item(cmd_edit)
      menu.add_item(cmd_box)
      menu.add_item(cmd_toggle)
      menu.add_separator
      menu.add_item(cmd_bom)
      menu.add_item(cmd_export_csv)
      menu.add_item(cmd_export_html)
      menu.add_separator
      menu.add_item(cmd_settings)
      menu.add_item(cmd_diagnostics)
      menu.add_item(cmd_about)

      toolbar = UI::Toolbar.new('SKP E-Plumb')
      toolbar.add_item(cmd_draw)
      toolbar.add_item(cmd_edit)
      toolbar.add_item(cmd_box)
      toolbar.add_item(cmd_toggle)
      toolbar.add_separator
      toolbar.add_item(cmd_bom)
      toolbar.add_item(cmd_settings)
      show_toolbar(toolbar)
    end

    # Show the toolbar reliably on first install (a plain restore sometimes
    # no-ops before the UI is ready), then restore its saved state afterwards.
    def show_toolbar(toolbar)
      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end
      UI.start_timer(0.3, false) do
        begin
          toolbar.restore
        rescue StandardError
          nil
        end
      end
    end
  end

  unless defined?(@ui_built) && @ui_built
    begin
      Menus.build
    rescue StandardError => e
      UI.messagebox("SKP E-Plumb no pudo crear el menú/barra:\n\n#{e.class}: #{e.message}")
    end
    @ui_built = true
  end
end
