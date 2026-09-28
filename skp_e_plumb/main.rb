# frozen_string_literal: true

require 'sketchup.rb'

begin
  require 'json'
rescue LoadError
  # JSON ships with SketchUp's Ruby; UIDialogs has a manual fallback encoder.
end

module SkpEPlumb
  # Load order matters: data -> codes -> geometry -> bom -> settings -> builder
  # -> tools -> ui -> menus. Any failure here is surfaced so it is never silent.
  dir = __dir__
  begin
    %w[
      version catalog codes geom_util bom settings builder picker cursors
      conduit_tool box_tool edit_tool ui_dialogs updater
    ].each { |f| require File.join(dir, "#{f}.rb") }
  rescue StandardError, ScriptError => e
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

    def activate_tool(name)
      tool = case name
             when 'draw' then ConduitTool.new
             when 'box' then BoxTool.new
             when 'edit' then EditTool.new
             end
      Sketchup.active_model.select_tool(tool) if tool
    end

    def apply_icon(cmd, base)
      small = File.join(ICONS, "#{base}_16.png")
      large = File.join(ICONS, "#{base}_24.png")
      cmd.small_icon = small if File.exist?(small)
      cmd.large_icon = large if File.exist?(large)
    end

    # Commands are created once and shared by the menu and the toolbar.
    def commands
      @commands ||= {
        draw: command('Dibujar tubería', 'conduit',
                      'Dibuja una tubería haciendo clic sobre muros, pisos y techos',
                      'Clic = punto · Doble clic/Enter = crear · Ctrl/Option = curva/codo · ' \
                      'Flechas = bloquear eje · Clic derecho = opciones') { activate_tool('draw') },
        box: command('Colocar caja', 'box', 'Coloca la caja activa sobre una superficie',
                     'Clic = colocar · Ctrl/Option/Tab = girar 90° · Clic derecho = elegir caja') { activate_tool('box') },
        edit: command('Editar tubería', 'edit', 'Edita una tubería por anclas',
                      'Clic en una tubería; arrastra anclas, inserta, borra, extiende y aplica con Enter.') do
          activate_tool('edit')
        end,
        bend: command('Alternar curva / codo', 'bend', 'Alterna doblar tubo ↔ codo prefabricado',
                      'Cambia cómo se resuelven las próximas curvas.') do
          mode = Settings.toggle_bend_mode!
          UIDialogs.refresh_settings
          Sketchup.set_status_text("Curvas: #{mode == :field ? 'DOBLAR TUBO' : 'CODO PREFABRICADO'}")
        end,
        bom: command('Materiales y revisión', 'bom', 'Lista de materiales y revisión normativa',
                     'Genera la lista de materiales del modelo y revisa la norma.') { UIDialogs.show_bom },
        panel: command('Panel de ajustes…', 'settings', 'Panel de SKP E-Plumb',
                       'Norma, tubería, curvas, cajas, conductores.') { UIDialogs.show_settings }
      }
    end

    def command(title, icon, tooltip, status, &block)
      c = UI::Command.new(title) { safe(title) { block.call } }
      c.tooltip = tooltip
      c.status_bar_text = status
      apply_icon(c, icon)
      c
    end

    def cmd_diagnostics
      UI::Command.new('Diagnóstico…') do
        safe('Diagnóstico') do
          model = Sketchup.active_model
          runs = 0
          Bom.each_run(model.entities) { runs += 1 }
          info = [
            "SKP E-Plumb v#{SkpEPlumb::VERSION}",
            "Ruby: #{RUBY_VERSION}",
            "SketchUp: #{Sketchup.version}",
            "HtmlDialog: #{defined?(UI::HtmlDialog) ? 'disponible' : 'NO disponible'}",
            "JSON: #{defined?(JSON) ? 'ok' : 'NO'}",
            "Norma activa: #{Codes.profile(Settings.profile)[:label]}",
            "Tuberías en el modelo: #{runs}"
          ]
          UI.messagebox(info.join("\n"))
        end
      end
    end

    def cmd_check_update
      c = UI::Command.new('Buscar actualizaciones…') do
        safe('Buscar actualizaciones') { Updater.check(interactive: true) }
      end
      c.tooltip = 'Verificar si hay una versión nueva en GitHub'
      c
    end

    def cmd_about
      UI::Command.new('Acerca de…') { safe('Acerca de') { UIDialogs.show_about } }
    end

    # After an update (installed VERSION differs from the last seen), show the
    # changelog for this version once. Runs on a timer so it never blocks load.
    def schedule_whatsnew
      seen = Sketchup.read_default(Settings::SECTION, 'seen_version', '')
      return if seen == SkpEPlumb::VERSION

      UI.start_timer(3, false) do
        begin
          Sketchup.write_default(Settings::SECTION, 'seen_version', SkpEPlumb::VERSION)
          UIDialogs.show_whatsnew(SkpEPlumb::VERSION)
        rescue StandardError
          nil
        end
      end
    rescue StandardError
      nil
    end

    # Silent once-a-day check on startup (if enabled); notifies only when there
    # is a newer version. Runs on a timer so it never blocks loading.
    def schedule_update_check
      return unless Settings.check_updates?

      today = Time.now.strftime('%Y-%m-%d')
      last = Sketchup.read_default(Settings::SECTION, 'last_update_check', '')
      return if last == today

      UI.start_timer(6, false) do
        begin
          Sketchup.write_default(Settings::SECTION, 'last_update_check', today)
          Updater.check(interactive: false)
        rescue StandardError
          nil
        end
      end
    rescue StandardError
      nil
    end

    def build
      c = commands
      menu = UI.menu('Extensions').add_submenu('SKP E-Plumb')
      menu.add_item(c[:draw])
      menu.add_item(c[:box])
      menu.add_item(c[:edit])
      menu.add_item(c[:bend])
      menu.add_separator
      menu.add_item(c[:bom])
      menu.add_item(c[:panel])
      menu.add_separator
      menu.add_item(cmd_diagnostics)
      menu.add_item(cmd_check_update)
      menu.add_item(cmd_about)

      toolbar = UI::Toolbar.new('SKP E-Plumb')
      toolbar.add_item(c[:draw])
      toolbar.add_item(c[:box])
      toolbar.add_item(c[:edit])
      toolbar.add_separator
      toolbar.add_item(c[:bom])
      toolbar.add_item(c[:panel])
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
      Menus.schedule_whatsnew
      Menus.schedule_update_check
    rescue StandardError => e
      UI.messagebox("SKP E-Plumb no pudo crear el menú/barra:\n\n#{e.class}: #{e.message}")
    end
    @ui_built = true
  end
end
