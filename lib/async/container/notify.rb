# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2020-2022, by Samuel Williams.

require_relative 'notify/pipe'
require_relative 'notify/socket'
require_relative 'notify/console'

module Async
	module Container
		module Notify
			@client = nil
			
			# Select the best available notification client.
			# We cache the client on a per-process basis. Because that's the relevant scope for process readiness protocols.
			def self.open!
				@client ||= (
					Pipe.open! ||
					Socket.open! ||
					Console.open!
				)
			end
		end
	end
end
