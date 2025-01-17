# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2018-2022, by Samuel Williams.

require "async/container/controller"

describe Async::Container::Controller do
	let(:controller) {subject.new}
	
	with '#reload' do
		it "can reuse keyed child" do
			input, output = IO.pipe
			
			controller.instance_variable_set(:@output, output)
			
			def controller.setup(container)
				container.spawn(key: "test") do |instance|
					instance.ready!
					
					sleep(0.2)
					
					@output.write(".")
					@output.flush
					
					sleep(0.4)
				end
				
				container.spawn do |instance|
					instance.ready!
					
					sleep(0.3)
					
					@output.write(",")
					@output.flush
				end
			end
			
			controller.start
			expect(input.read(2)).to be == ".,"
			
			controller.reload
			
			expect(input.read(1)).to be == ","
			controller.wait
		end
	end
	
	with '#start' do
		it "can start up a container" do
			expect(controller).to receive(:setup)
			
			controller.start
			
			expect(controller).to be(:running?)
			expect(controller.container).not.to be_nil
			
			controller.stop
			
			expect(controller).not.to be(:running?)
			expect(controller.container).to be_nil
		end
		
		it "can spawn a reactor" do
			def controller.setup(container)
				container.async do |task|
					task.sleep 1
				end
			end
			
			controller.start
			
			statistics = controller.container.statistics
			
			expect(statistics.spawns).to be == 1
			
			controller.stop
		end
		
		it "propagates exceptions" do
			def controller.setup(container)
				raise "Boom!"
			end
			
			expect do
				controller.run
			end.to raise_exception(Async::Container::SetupError)
		end
	end
	
	with 'signals' do
		let(:controller_path) {File.expand_path(".dots.rb", __dir__)}
		
		let(:pipe) {IO.pipe}
		let(:input) {pipe.first}
		let(:output) {pipe.last}
		
		let(:pid) {@pid}
		
		def before
			@pid = Process.spawn("bundle", "exec", controller_path, out: output)
			output.close
			
			super
		end
		
		def after
			Process.kill(:TERM, @pid)
			Process.wait(@pid)
			
			super
		end
		
		it "restarts children when receiving SIGHUP" do
			expect(input.read(1)).to be == '.'
			
			Process.kill(:HUP, pid)
			
			expect(input.read(2)).to be == 'I.'
		end
		
		it "exits gracefully when receiving SIGINT" do
			expect(input.read(1)).to be == '.'
			
			Process.kill(:INT, pid)
			
			expect(input.read).to be == 'I'
		end
		
		it "exits gracefully when receiving SIGTERM" do
			expect(input.read(1)).to be == '.'
			
			Process.kill(:TERM, pid)
			
			expect(input.read).to be == 'T'
		end
	end
end
