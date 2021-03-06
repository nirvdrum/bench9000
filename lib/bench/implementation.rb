# Copyright (c) 2014, 2015 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
# 
# Eclipse Public License version 1.0
# GNU General Public License version 2
# GNU Lesser General Public License version 2.1

module Bench

  class Implementation

    BEFORE_WARMUP_TIME = 30
    WARMUP_WINDOW_SIZE = 20
    WARMED_UP_RELATIVE_RANGE = 0.1
    MAX_WARMUP = 100
    MAX_WARMUP_TIME = 4 * 60
    SAMPLES_COUNT = 10

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def measure(flags, benchmark)
      command = "bash -c \"#{command(benchmark)}\""

      puts command if flags.has_key? "--show-commands"

      warming_up = true
      warmup_window = []
      warmup_samples = []
      samples = []

      overall_time = Time.now

      IO.popen command, "r+" do |subprocess|
        while true
          line = subprocess.gets
          
          if line.nil? || line == "error"
            return :failed
          end

          unless line.match(/\d+\.\d+/)
            STDERR.puts line
            next
          end

          time = line.to_f
          puts time if flags.has_key? "--show-samples"

          elapsed_time = Time.now - overall_time

          if elapsed_time < BEFORE_WARMUP_TIME
            warmup_samples.push time
            
            subprocess.puts "continue"
          elsif warming_up
            warmup_samples.push time

            warmup_window.shift if warmup_window.size == WARMUP_WINDOW_SIZE
            warmup_window.push time
            window_relative_range = Stats.range(warmup_window) / Stats.mean(warmup_window)

            if warmup_window.size == WARMUP_WINDOW_SIZE && window_relative_range < WARMED_UP_RELATIVE_RANGE
              warming_up = false
              warmup_samples = warmup_samples.reverse.drop(WARMUP_WINDOW_SIZE).reverse
              samples = warmup_window
            elsif warmup_samples.size > MAX_WARMUP || elapsed_time > MAX_WARMUP_TIME
              puts "warning: #{@name} #{benchmark} never warmed up!"
              warming_up = false
            end

            subprocess.puts "continue"
          else
            samples.push time

            if samples.size < SAMPLES_COUNT
              subprocess.puts "continue"
            else
              subprocess.puts "stop"
              break
            end
          end
        end
      end

      raise "not enough warmup samples" if warmup_samples.nil?
      raise "not enough samples" if samples.nil? || samples.size < SAMPLES_COUNT
      
      Measurement.new(warmup_samples, samples)
    end

    def to_s
      @name
    end

  end

  HARNESS_DIR = File.join(File.dirname(__FILE__), '..')

  class RbenvImplementation < Implementation

    def initialize(name, version, flags)
      @name = name
      @version = version
      @flags = flags
    end

    def command(benchmark)
      "~/.rbenv/versions/#{@version}/bin/ruby #{@flags} -I#{HARNESS_DIR} #{benchmark.flags} #{benchmark.file}"
    end

  end

  class BinaryImplementation < Implementation

    def initialize(name, binary, flags)
      @name = name
      @binary = binary
      @flags = flags
    end

    def command(benchmark)
      "#{@binary} #{@flags} -I#{HARNESS_DIR} #{benchmark.flags} #{benchmark.file}"
    end

  end

end
