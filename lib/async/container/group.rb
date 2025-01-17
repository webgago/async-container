# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2019-2022, by Samuel Williams.

require 'fiber'
require 'async/clock'

require_relative 'error'

module Async
	module Container
		# Manages a group of running processes.
		class Group
			# Initialize an empty group.
			def initialize
				@running = {}
				
				# This queue allows us to wait for processes to complete, without spawning new processes as a result.
				@queue = nil
			end
			
			# @attribute [Hash(IO, Fiber)] the running tasks, indexed by IO.
			attr :running
			
			# Whether the group contains any running processes.
			# @returns [Boolean]
			def running?
				@running.any?
			end
			
			# Whether the group contains any running processes.
			# @returns [Boolean]
			def any?
				@running.any?
			end
			
			# Whether the group is empty.
			# @returns [Boolean]
			def empty?
				@running.empty?
			end
			
			# Sleep for at most the specified duration until some state change occurs.
			def sleep(duration)
				self.resume
				self.suspend
				
				self.wait_for_children(duration)
			end
			
			# Begin any outstanding queued processes and wait for them indefinitely.
			def wait
				self.resume
				
				while self.running?
					self.wait_for_children
				end
			end
			
			# Interrupt all running processes.
			# This resumes the controlling fiber with an instance of {Interrupt}.
			def interrupt
				Console.logger.debug(self, "Sending interrupt to #{@running.size} running processes...")
				@running.each_value do |fiber|
					fiber.resume(Interrupt)
				end
			end
			
			# Terminate all running processes.
			# This resumes the controlling fiber with an instance of {Terminate}.
			def terminate
				Console.logger.debug(self, "Sending terminate to #{@running.size} running processes...")
				@running.each_value do |fiber|
					fiber.resume(Terminate)
				end
			end
			
			# Stop all child processes using {#terminate}.
			# @parameter timeout [Boolean | Numeric | Nil] If specified, invoke a graceful shutdown using {#interrupt} first.
			def stop(timeout = 1)
				# Use a default timeout if not specified:
				timeout = 1 if timeout == true
				
				if timeout
					start_time = Async::Clock.now
					
					self.interrupt
					
					while self.any?
						duration = Async::Clock.now - start_time
						remaining = timeout - duration
						
						if remaining >= 0
							self.wait_for_children(duration)
						else
							self.wait_for_children(0)
							break
						end
					end
				end
				
				# Terminate all children:
				self.terminate
				
				# Wait for all children to exit:
				self.wait
			end
			
			# Wait for a message in the specified {Channel}.
			def wait_for(channel)
				io = channel.in
				
				@running[io] = Fiber.current
				
				while @running.key?(io)
					result = Fiber.yield
					
					if result == Interrupt
						channel.interrupt!
					elsif result == Terminate
						channel.terminate!
					elsif message = channel.receive
						yield message
					else
						return channel.wait
					end
				end
			ensure
				@running.delete(io)
			end
			
			protected
			
			def wait_for_children(duration = nil)
				if !@running.empty?
					# Maybe consider using a proper event loop here:
					readable, _, _ = ::IO.select(@running.keys, nil, nil, duration)
					
					readable&.each do |io|
						@running[io].resume
					end
				end
			end
			
			def yield
				if @queue
					fiber = Fiber.current
					
					@queue << fiber
					Fiber.yield
				end
			end
			
			def suspend
				@queue ||= []
			end
			
			def resume
				if @queue
					queue = @queue
					@queue = nil
					
					queue.each(&:resume)
				end
			end
		end
	end
end
