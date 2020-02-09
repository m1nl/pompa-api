# frozen_string_literal: true

require 'fiber'

module ModelSync
  class Launcher
    QUANTUM = 1
    WATCHDOG = 'watchdog'

    def initialize(options = {})
      @options = options

      @done = false
      @mutex = Mutex.new

      @threads = []
      @consumers = []

      if options[:producer]
        @producer = Producer.new
        @threads.push(@producer)
      end
  
      options[:consumers].times { @consumers.push(Consumer.new) }
      @threads.concat(@consumers)
    end

    def run
      @mutex.synchronize do
        stop if alive?

        @threads.each { |c| c.run }

        @watchdog = Thread.new do
          Thread.current[:name] = WATCHDOG
          watchdog_thread
          rescue Exception => e
            logger.error("#{e.class.name}: #{e.message}")
            logger.backtrace(e)
            raise e
        end
      end
    end

    def stop
      @mutex.synchronize do
        @done = true

        if alive?
          fibers = []

          @threads.each do |c|
            fibers.push(Fiber.new { c.stop { Fiber.yield } })
          end

          fibers.each { |f| f.resume if f.alive? }
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          loop do
            break if @threads.all? { |t| !t.alive? }
            sleep QUANTUM

            time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if (time - start) >= ModelSync::TIMEOUT * 2
          end

          @watchdog.raise Interrupt if alive?
          fibers.each { |f| f.resume if f.alive? }
        end

        ensure
          @watchdog = nil
          @done = false
      end
    end

    def options
      @options
    end

    def alive?
      !@watchdog.nil? && @watchdog.alive?
    end

    private
      def logger
        ModelSync.logger
      end

      def done?
        @done
      end

      def watchdog_thread
        logger.info("Watchdog thread started")

        loop do
          break if done?

          sleep ModelSync::TIMEOUT
          break if done?

          @threads.each do |t|
            @mutex.synchronize do
              if !t.alive?
                logger.info("Restarting #{t.name} thread")
                t.run
              end
            end

            rescue StandardError => e
              logger.error("#{e.class.name}: #{e.message}")
              logger.backtrace(e)
          end
        end

        rescue Interrupt
        ensure
          logger.info("Watchdog thread stopped")
      end
  end
end
