module Nanoc3::CLI::Commands

  class Compile < Cri::Command # :nodoc:

    def name
      'compile'
    end

    def aliases
      []
    end

    def short_desc
      'compile pages and assets of this site'
    end

    def long_desc
      'Compile all pages and all assets of the current site. If an identifier is ' +
      'given, only the page or asset with the given identifier will be compiled. ' +
      "\n\n" +
      'By default, only pages and assets that are outdated will be ' +
      'compiled. This can speed up the compilation process quite a bit, ' +
      'but pages that include content from other pages may have to be ' +
      'recompiled manually. In order to compile objects even when they are ' +
      'outdated, use the --force option.' +
      "\n\n" +
      'Both pages and assets will be compiled by default. To disable the ' +
      'compilation of assets or pages, use the --no-assets and --no-pages ' +
      'options, respectively.'
    end

    def usage
      "nanoc compile [options] [identifier]"
    end

    def option_definitions
      [
        # --all
        {
          :long => 'all', :short => 'a', :argument => :forbidden,
          :desc => 'alias for --force (DEPRECATED)'
        },
        # --force
        {
          :long => 'force', :short => 'f', :argument => :forbidden,
          :desc => 'compile pages and assets even when they are not outdated'
        },
        # --only-pages
        {
          :long => 'no-pages', :short => 'P', :argument => :forbidden,
          :desc => 'don\'t compile pages'
        },
        # --only-assets
        {
          :long => 'no-assets', :short => 'A', :argument => :forbidden,
          :desc => 'don\'t compile assets'
        }
      ]
    end

    def run(options, arguments)
      # Make sure we are in a nanoc site directory
      @base.require_site
      @base.site.load_data

      # Check presence of --all option
      if options.has_key?(:all)
        $stderr.puts "Warning: the --all option is deprecated; please use --force instead."
      end

      # Find object(s) to compile
      if arguments.size == 0
        # Find all pages and/or assets
        if options.has_key?(:'no-pages')
          objs = @base.site.assets
        elsif options.has_key?(:'no-assets')
          objs = @base.site.pages
        else
          objs = nil
        end
      else
        # Find object(s) with given identifier(s)
        objs = arguments.map do |identifier|
          # Find object
          identifier = identifier.cleaned_identifier
          obj = @base.site.pages.find { |page| page.identifier == identifier }
          obj = @base.site.assets.find { |asset| asset.identifier == identifier } if obj.nil?

          # Ensure object
          if obj.nil?
            $stderr.puts "Unknown page or asset: #{identifier}"
            exit 1
          end

          obj
        end
      end

      # Compile site
      begin
        # Give feedback
        puts "Compiling #{objs.nil? ? 'site' : 'objects'}..."

        # Initialize profiling stuff
        time_before = Time.now
        @filter_times ||= {}
        @times_stack  ||= []
        setup_notifications

        # Compile
        @base.site.compiler.run(
          objs,
          :force => options.has_key?(:all) || options.has_key?(:force)
        )

        # Find reps
        page_reps  = @base.site.pages.map  { |p| p.reps }.flatten
        asset_reps = @base.site.assets.map { |a| a.reps }.flatten
        reps       = page_reps + asset_reps

        # Show skipped reps
        reps.select { |r| !r.compiled? }.each do |rep|
          duration = @rep_times[rep.raw_path]
          Nanoc3::CLI::Logger.instance.file(:low, :skip, rep.raw_path, duration)
        end

        # Show non-written reps
        reps.select { |r| r.compiled? && !r.written? }.each do |rep|
          duration = @rep_times[rep.raw_path]
          Nanoc3::CLI::Logger.instance.file(:low, :'not written', rep.raw_path, duration)
        end

        # Give general feedback
        puts
        puts "No objects were modified." unless reps.any? { |r| r.modified? }
        puts "#{objs.nil? ? 'Site' : 'Object'} compiled in #{format('%.2f', Time.now - time_before)}s."

        if options.has_key?(:verbose)
          print_state_feedback(reps)
          print_profiling_feedback(reps)
        end
      rescue Interrupt => e
        exit
      rescue Exception => e
        print_error(e)
      end
    end

  private

    def setup_notifications
      Nanoc3::NotificationCenter.on(:compilation_started) do |rep|
        rep_compilation_started(rep)
      end
      Nanoc3::NotificationCenter.on(:compilation_ended) do |rep|
        rep_compilation_ended(rep)
      end
      Nanoc3::NotificationCenter.on(:filtering_started) do |rep, filter_name|
        rep_filtering_started(rep, filter_name)
      end
      Nanoc3::NotificationCenter.on(:filtering_ended) do |rep, filter_name|
        rep_filtering_ended(rep, filter_name)
      end
    end

    def print_state_feedback(reps)
      # Categorise reps
      rest              = reps
      created, rest     = *rest.partition { |r| r.created? }
      modified, rest    = *rest.partition { |r| r.modified? }
      skipped, rest     = *rest.partition { |r| !r.compiled? }
      not_written, rest = *rest.partition { |r| r.compiled? && !r.written? }
      identical         = rest

      # Print
      puts
      puts format('  %4d  created',   created.size)
      puts format('  %4d  modified',  modified.size)
      puts format('  %4d  skipped',   skipped.size)
      puts format('  %4d  not written', not_written.size)
      puts format('  %4d  identical', identical.size)
    end

    def print_profiling_feedback(reps)
      # Get max filter length
      max_filter_name_length = @filter_times.keys.map { |k| k.to_s.size }.max
      return if max_filter_name_length.nil?

      # Print warning if necessary
      if reps.any? { |r| !r.compiled? }
        $stderr.puts
        $stderr.puts "Warning: profiling information may not be accurate because " +
                     "some objects were not compiled."
      end

      # Print header
      puts
      puts ' ' * max_filter_name_length + ' | count    min    avg    max     tot'
      puts '-' * max_filter_name_length + '-+-----------------------------------'

      @filter_times.to_a.sort_by { |r| r[1] }.each do |row|
        # Extract data
        filter_name, samples = *row

        # Calculate stats
        count = samples.size
        min   = samples.min
        tot   = samples.inject { |memo, i| memo + i}
        avg   = tot/count
        max   = samples.max

        # Format stats
        count = format('%4d',   count)
        min   = format('%4.2f', min)
        avg   = format('%4.2f', avg)
        max   = format('%4.2f', max)
        tot   = format('%5.2f', tot)

        # Output stats
        filter_name = format("%#{max_filter_name_length}s", filter_name)
        puts "#{filter_name} |  #{count}  #{min}s  #{avg}s  #{max}s  #{tot}s"
      end
    end

    def print_error(error)
      # Get rep
      rep = (@base.site.compiler.stack || []).select { |i| i.is_a?(Nanoc3::PageRep) || i.is_a?(Nanoc3::AssetRep) }[-1]
      rep_name = rep.nil? ? 'the site' : "#{rep.item.identifier} (rep #{rep.name})"

      # Build message
      case error
      when Nanoc3::Errors::UnknownLayoutError
        message = "Unknown layout: #{error.message}"
      when Nanoc3::Errors::UnknownFilterError
        message = "Unknown filter: #{error.message}"
      when Nanoc3::Errors::CannotDetermineFilterError
        message = "Cannot determine filter for layout: #{error.message}"
      when Nanoc3::Errors::RecursiveCompilationError
        message = "Recursive call to page content."
      when Nanoc3::Errors::NoLongerSupportedError
        message = "No longer supported: #{error.message}"
      when Nanoc3::Errors::NoRulesFileFoundError
        message = "No rules file found"
      when Nanoc3::Errors::NoMatchingRuleFoundError
        message = "No matching rule found"
      else
        message = "Error: #{error.message}"
      end

      # Print message
      $stderr.puts
      $stderr.puts "ERROR: An exception occured while compiling #{rep_name}."
      $stderr.puts
      $stderr.puts "If you think this is a bug in nanoc, please do report it at " +
                   "<http://projects.stoneship.org/trac/nanoc/newticket> -- thanks!"
      $stderr.puts
      $stderr.puts 'Message:'
      $stderr.puts '  ' + message
      $stderr.puts
      $stderr.puts 'Compilation stack:'
      (@base.site.compiler.stack || []).reverse.each do |item|
        if item.is_a?(Nanoc3::PageRep) # page rep
          $stderr.puts "  - [page]   #{item.page.identifier} (rep #{item.name})"
        elsif item.is_a?(Nanoc3::AssetRep) # asset rep
          $stderr.puts "  - [asset]  #{item.asset.identifier} (rep #{item.name})"
        else # layout
          $stderr.puts "  - [layout] #{item.identifier}"
        end
      end
      $stderr.puts
      $stderr.puts 'Backtrace:'
      $stderr.puts error.backtrace.map { |t| '  - ' + t }.join("\n")
    end

    def rep_compilation_started(rep)
      # Profile compilation
      @rep_times ||= {}
      @rep_times[rep.raw_path] = Time.now
    end

    def rep_compilation_ended(rep)
      # Profile compilation
      @rep_times ||= {}
      @rep_times[rep.raw_path] = Time.now - @rep_times[rep.raw_path]

      # Skip if not outputted
      return unless rep.written?

      # Get action and level
      action, level = *if rep.created?
        [ :create, :high ]
      elsif rep.modified?
        [ :update, :high ]
      elsif !rep.compiled?
        [ nil, nil ]
      else
        [ :identical, :low ]
      end

      # Log
      unless action.nil?
        duration = @rep_times[rep.raw_path]
        Nanoc3::CLI::Logger.instance.file(level, action, rep.raw_path, duration)
      end
    end

    def rep_filtering_started(rep, filter_name)
      @times_stack.push(Time.now)
    end

    def rep_filtering_ended(rep, filter_name)
      # Get last time
      time_start = @times_stack.pop

      # Update times
      @filter_times[filter_name.to_sym] ||= []
      @filter_times[filter_name.to_sym] << Time.now - time_start
    end

  end

end
