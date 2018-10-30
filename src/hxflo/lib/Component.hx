package hxflo.lib;

import haxe.DynamicAccess;

using tink.CoreApi;

import haxe.ds.*;

import hxflo.lib.Ports;

typedef TBracketContext = {
	var In:Dynamic, var Out:Dynamic
}

/**
 * NoFlo Component Base class
 *
 * The `noflo.Component` interface provides a way to instantiate
 * and extend NoFlo components.
 */
class Component extends EventEmitter {
	public var baseDir:String;
	public var componentName:String;
	public var options:Dynamic;
	public var description:String;
	public var icon:String;
	public var inPorts:Dynamic;
	public var outPorts:Dynamic;
	public var started:Bool;
	public var load:Int;
	public var ordered:Bool;
	public var autoOrdering:Dynamic;
	public var outputQ:Array<Dynamic>;
	public var bracketContext:TBracketContext;
	public var forwardBrackets:Dynamic;
	public var activateOnInput:Bool;

	public dynamic function handle(input:ProcessInput, output:ProcessOutput, ?context:ProcessContext):Void {};

	public var nodeId:Dynamic;

	public function new(?options:Dynamic) {
		super();

		this.options = options != null ? options : {};

		/**
		 * Prepare inports, if any were given in options.
		 * They can also be set up imperatively after component
		 * instantiation by using the `component.inPorts.add`
		 * method.
		 */
		if (options.inports == null) {
			options.inPorts = {};
		}
		if (Std.is(options.inPorts, Ports.InPorts)) {
			this.inPorts = options.inPorts;
		} else {
			this.inPorts = new Ports.InPorts(options.inPorts);
		}

		/**
		 * Prepare outports, if any were given in options.
		 * They can also be set up imperatively after component
		 * instantiation by using the `component.outPorts.add`
		 * method.
		 */
		if (options.outports == null) {
			options.outPorts = {};
		}
		if (Std.is(options.outPorts, Ports.InPorts)) {
			this.outPorts = options.outPorts;
		} else {
			this.outPorts = new Ports.OutPorts(options.outPorts);
		}

		// Set the default component icon and description
		this.icon = options.icon != null ? options.icon : null;
		this.description = options.description != null ? options.description : null;

		// Initially the component is not started
		this.started = false;
		this.load = 0;

		// Whether the component should keep send packets
		// out in the order they were received
		this.ordered = options.ordered == true ? options.ordered : false;
		this.autoOrdering = options.autoOrdering != null ? options.autoOrdering : null;

		// Queue for handling ordered output packets
		this.outputQ = [];

		// Context used for bracket forwarding
		this.bracketContext = {
			In: {},
			Out: {}
		};

		// Whether the component should activate when it receives packets
		this.activateOnInput = options.activateOnInput == true ? options.activateOnInput : true;

		// Bracket forwarding rules. By default we forward
		// brackets from `in` port to `out` and `error` ports.
		this.forwardBrackets = {
			In: ['out', 'error'],
			Out: null
		};

		if (Reflect.hasField(options, 'forwardBrackets')) {
			this.forwardBrackets = options.forwardBrackets;
		}

		/**
		 * The component's process function can either be
		 * passed in options, or given imperatively after
		 * instantation using the `component.process` method.
		 */
		if (Reflect.isFunction(options.process)) {
			process(options.process);
		}
	}

	public function getDescription():String
		return this.description;

	public function isReady():Bool
		return true;

	public function isSubraph():Bool
		return false;

	public function setIcon(icon:String) {
		emit('icon', [icon]);
	}

	public function getIcon():String
		return icon;

	/**
	 * Error emitting helper
	 *
	 * If component has an `error` outport that is connected, errors
	 * are sent as IP objects there. If the port is not connected,
	 * errors are thrown.
	 *
	 * @param e
	 * @param groups
	 * @param errorPort
	 * @param scope
	 */
	public function error(e:String, groups:Array<Dynamic> = [], errorPort:String = 'error', scope:Dynamic = null) {
		var errPort:OutPort = Reflect.field(Type.getClass(this.outPorts), errorPort);
		if (errPort != null && (errPort.isAttached() || !errPort.isRequired())) {
			for (group in groups) {
				errPort.openBracket(group, {
					scope: scope
				});
			}
			errPort.data(e, {
				scope: scope
			});
			for (group in groups) {
				errPort.closeBracket(group, {
					scope: scope
				});
			}
			return;
		}

		throw e;
	}

	/**
	 * Setup
	 *
	 * The setUp method is for component-specific initialization.
	 * Called at network start-up.
	 *
	 * Override in component implementation to do component-specific
	 * setup work.
	 *
	 * @return Promise<Dynamic>
	 */
	public function setUp():Promise<Dynamic> {
		return Future.async(function(cb) {});
	}

	/**
	 * Teardown
	 *
	 * The tearDown method is for component-specific initialization.
	 * Called at network shutdown.
	 *
	 * Override in component implementation to do component-specific
	 * cleanup work, like clearing any accumulated state.
	 *
	 * @return Promise<Dynamic>
	 */
	public function tearDown():Promise<Dynamic> {
		return Future.async(function(cb) {});
	}

	/**
	 * Start
	 *
	 * Called when network starts. This sets calls the setUp
	 * method and sets the component to a started state.
	 *
	 * @return Promise<Dynamic>
	 */
	public function start():Promise<Dynamic> {
		return Future.async(function(cb) {
			if (isStarted()) {
				cb(Success(null));
				return;
			}
			setUp().handle(function(o) {
				if (!o.isSuccess()) {
					cb(Failure(null));
					return;
				}
				started = true;
				emit('start');
				cb(Success(null));
				return;
			});

			return;
		});
	}

	/**
	 * Shutdown
	 *
	 * Called when network is shut down. This sets calls the
	 * tearDown method and sets the component back to a
	 * non-started state.
	 *
	 * The callback is called when tearDown finishes and
	 * all active processing contexts have ended.
	 *
	 * @return Promise<Dynamic>
	 */
	public function shutdown():Promise<Dynamic> {
		return Future.async(function(cb) {
			var finalize = function() {
				// Clear contents of inport buffers
				var inPorts = this.inPorts.ports != null ? this.inPorts.ports : this.inPorts;
				var iterator:Array<String> = null;

				if (Reflect.isObject(inPorts)) {
					iterator = Reflect.fields(inPorts);
				} else {
					iterator = Reflect.fields(Type.getClass(inPorts));
				}
				for (portName in iterator) {
					var inPort = null;
					if (Reflect.isObject(inPorts)) {
						inPort = Reflect.field(inPorts, portName);
					} else {
						inPort = Reflect.field(Type.getClass(inPorts), portName);
					}
					if (!Reflect.isFunction(inPort.clear)) {
						continue;
					}
					inPort.clear();
				}
				this.bracketContext = {
					In: {},
					Out: {}
				};
				if (!isStarted()) {
					cb(Success(null));
				}

				started = false;

				emit('end');
				cb(Success(null));
				return;
			};

			// Tell the component that it is time to shut down
			this.tearDown().handle(function(o) {
				if (!o.isSuccess()) {
					cb(Failure(null));
				}

				if (load > 0) {
					// Some in-flight processes, wait for them to finish
					var checkLoad = function(args:Array<Dynamic>) {
						var load:Int = args[0];
						if (load > 0)
							return;
						removeListener('deactivate', new EventCallback(checkLoad));
						finalize();
						return;
					};

					on('deactivate', checkLoad);
					return;
				}
				finalize();
				return;
			});
			return;
		});
	}

	public function isStarted():Bool
		return started;

	/**
	 * Ensures braket forwarding map is correct for the existing ports
	 */
	public function prepareForwarding() {
		for (inPort in Reflect.fields(forwardBrackets)) {
			var outPorts = Reflect.field(forwardBrackets, inPort);

			if (!this.inPorts.ports.exists(inPort)) {
				Reflect.deleteField(forwardBrackets, inPort);
				continue;
			}
			var tmp = [];
			for (outPort in Reflect.fields(outPorts)) {
				if (this.outPorts.ports.exists(outPort)) {
					tmp.push(outPort);
				}
				if (tmp.length == 0) {
					Reflect.deleteField(forwardBrackets, inPort);
				} else {
					Reflect.setField(forwardBrackets, inPort, tmp);
				}
			}
		}
	}

	/**
	 * Sets process handler function
	 */
	public function process(handler:ProcessInput->ProcessOutput->?ProcessContext->Void):Component {
		if (!Reflect.isFunction(handler)) {
			throw "Process handler must be a function";
		}
		if (inPorts == null) {
			"Component ports must be defined before process function";
		}

		prepareForwarding();

		this.handle = handler;
		var _ports:StringMap<Dynamic> = cast inPorts.ports;
		for (name in _ports.keys()) {
			var port = cast(_ports.get(name), InPort);
			if (port.name == null) {
				port.name = name;
			}
			port.on('ip',
				new EventCallback(function(args) {
					var ip:IP = cast args[0];
					handleIP(ip, port);
				}));
		}

		return this;
	}

	/**
	 * Method for checking if a given inport is set up for
	 * automatic bracket forwarding
	 *
	 * @param port
	 * @return Bool
	 */
	public function isForwardingInPort(port:Dynamic):Bool {
		var portName:String = null;
		if (Std.is(port, String)) {
			portName = port;
		} else {
			portName = port.name;
		}

		if (Reflect.hasField(forwardBrackets, portName)) {
			return true;
		}
		return false;
	}

	/**
	 *
	 * @param port
	 * @return Bool
	 */
	public function isForwardingOutPort(inport:Dynamic, outport:Dynamic):Bool {
		var inportName:String = null;
		if (Std.is(inport, String)) {
			inportName = port;
		} else {
			inportName = port.name;
		}

		var outportName:String = null;
		if (Std.is(outport, String)) {
			outportName = port;
		} else {
			outportName = port.name;
		}

		if (!Reflect.hasField(forwardBrackets, inportName)) {
			return false;
		}

		if (Reflect.field(forwardBrackets, inportName).indexOf(outportName) != -1) {
			return true;
		}

		return false;
	}

	public function isOrdered() {
		if (ordered) {
			return true;
		}

		if (autoOrdering != null) {
			return true;
		}

		return false;
	}

	/**
	 * Handling IP objects
	 *
	 * The component has received an Information Packet. Call the
	 * processing function so that firing pattern preconditions can
	 * be checked and component can do processing as needed.
	 *
	 * @param ip
	 * @param port
	 */
	public function handleIP(ip:IP, port:InPort) {
		if (!port.options.triggering) {
			// If port is non-triggering, we can skip the process function call
			return;
		}

		if (ip.type == 'openBracket' && this.autoOrdering == null && !ordered) {
			// Switch component to ordered mode when receiving a stream unless
			// auto-ordering is disabled

			trace('${this.nodeId} port "${port.name}" entered auto-ordering mode');
			autoOrdering = true;
		}

		// Initialize the result object for situations where output needs
		// to be queued to be kept in order
		var result = {};

		if (isForwardingInPort(port)) {
			// For bracket-forwarding inports we need to initialize a bracket context
			// so that brackets can be sent as part of the output, and closed after.
			if (ip.type == 'openBracket') {
				// For forwarding ports openBrackets don't fire
				return;
			}

			if (ip.type == 'closeBracket') {
				/**
				 * For forwarding ports closeBrackets don't fire
				 * However, we need to handle several different scenarios:
				 * A. There are closeBrackets in queue before current packet
				 * B. There are closeBrackets in queue after current packet
				 * C. We've queued the results from all in-flight processes and
				 * 		new closeBracket arrives
				 */
				var buf = port.getBuffer(ip.scope, ip.index);
				var dataPackets = buf.filter(function(ip) {
					return ip.type == 'data';
				});

				if (this.outputQ.length >= load && dataPackets.length == 0) {
					if (buf[0] != ip) {
						return;
					}

					// Remove from buffer
					port.get(ip.scope, ip.index);
					context = this.getBracketContext('in', port.name, ip.scope, ip.index).pop();
					context.closeIp = ip;
					trace('${this.nodeId} closeBracket-C from "${context.source}" to ${context.ports}: "${ip.data}"');

					var result = {
						__resolved: true,
						__bracketClosingAfter: [context]
					};

					this.outputQ.push(result);
					this.processOutputQueue();
					// Check if buffer contains data IPs. If it does, we want to allow
					// firing
					if (dataPackets.length == 0) {
						return;
					}
				}
			}
		}

		// Prepare the input/output pair
		var context:ProcessContext = new ProcessContext(ip, this, port, result);
		var input:ProcessInput = new ProcessInput(this.inPorts, context);
		var output:ProcessOutput = new ProcessOutput(this.outPorts, context);

		try {
			// Call the processing function
			this.handle(input, output, context);
		} catch (error:Dynamic) {
			var e = error;
			this.deactivate(context);
			output.sendDone(e);
		}

		if (context.activated) {
			return;
		}

		// If receiving an IP object didn't cause the component to
		// activate, log that input conditions were not met
		if (port.isAddressable()) {
			trace('${this.nodeId} packet on "${port.name}[${ip.index}]" didn\'t match preconditions:${ip.type}');
			return;
		}
		trace('${this.nodeId} packet on "${port.name}" didn\'t match preconditions:${ip.type}');
	}

	/**
	 * Get the current bracket forwarding context for an IP object
	 * @param type
	 * @param port
	 * @param scope
	 * @param idx
	 */
	public function getBracketContext(type:String, port:Dynamic, scope:String, idx:Dynamic):Array<Dynamic> {
		var name = Ports.normalizePortName(port).name;
		var index = Ports.normalizePortName(port).index;
		var portsList = [];
		if(idx != null){
			index = idx;
		}
		if(type == 'in'){
			portsList = inPorts;
		}else {
			portsList = outPorts;
		}

		if(Reflect.field(portsList, name).isAddressable()){
			port = '${name}[${index}]';
		}
		// Ensure we have a bracket context for the current scope
		var bracketType = Reflect.field(bracketContext, type);
		if(!Reflect.hasField(bracketType, port)) Reflect.setField(bracketType, port, {});
		var bracketPort = Reflect.field(bracketType, port);
		if(!Reflect.hasField(bracketPort, scope)) Reflect.setField(bracketPort, scope, []);
		return cast Reflect.field(bracketPort, scope);
	}

	/**
	 * Add an IP object to the list of results to be sent in
	 * @param result 
	 * @param port 
	 * @param ip 
	 * @param before 
	 */
	public function addToResult(result:Dynamic, port:Dynamic, ip:IP, before:Bool = false){
		var name = Ports.normalizePortName(port).name;
		var index = Ports.normalizePortName(port).index;
		var methodName = null;
		var idx = null;
		if(before){
			methodName = 'unshift';
		} else {
			methodName = 'push';
		}

		if (Reflect.field(outPorts, name).isAddressable()){
			if(index != null){
				idx = index;
			} else {
				idx = ip.index;
			}

			if(Reflect.hasField(result, name) && Reflect.field(result, name) == null) return Reflect.setField(result, name, {});
			if(!Reflect.hasField(Reflect.field(result, name), idx)) return Reflect.setField(Reflect.field(result, name), idx, []);
			ip.index = idx;

			var method:IP->Void = cast Reflect.field(Reflect.field(Reflect.field(result, name), idx), methodName);
			method(ip);
		}
	}

	/**
	 * Get contexts that can be forwarded with this in/outport pair.
	 * @param inport 
	 * @param outport 
	 * @param contexts 
	 */
	public function getForwardableContexts(inport:Dynamic, outport:Dynamic, contexts:Array<Dynamic>){
		var name = Ports.normalizePortName(outport).name;
		var index = Ports.normalizePortName(outport).index;		
		var forwardable = [];
		for(ctx in contexts){
			var idx = contexts.indexOf(ctx);
			// No forwarding to this outport
			if(!isForwardingOutport(inport, name)){
				return null;
			}
			// We have already forwarded this context to this outport
			if(ctx.ports.indexOf(outport) == -1){
				return null;
			}

			// See if we have already forwarded the same bracket from another
			// inport
			var outContext = getBracketContext('out', name, ctx.ip.scope, index)[idx];
			if(outContext != null){
				if(outContext.ip.data == ctx.ip.data && outContext.ports.indexOf(outport) == -1){
					return null;
				}
			}
			forwardable.push(ctx);
		}
		return forwardable;
	}

	/**
	 * Add any bracket forwards needed to the result queue
	 * @param result 
	 */
	public function addBracketForwards(result:Dynamic){

	}

	

	public function processOutputQueue(){

	}

	/**
	 * Signal that component has activated. There may be multiple
	 * activated contexts at the same time
	 * @param context
	 */
	public function activate(context:ProcessContext) {
		if (context.activated) {
			return;
		}

		context.activated = true;
		context.deactivated = false;
		this.load++;
		emit('activate', [load]);

		if (ordered || autoOrdering != null) {
			outputQ.push(context.result);
		}
	}

	/**
	 * Signal that component has deactivated. There may be multiple
	 * activated contexts at the same time
	 *
	 * @param context
	 */
	public function deactivate(context:ProcessContext) {
		if (context.deactivated) {
			return;
		}
		context.deactivated = true;
		context.activated = false;

		if (isOrdered()) {
			this.processOutputQueue();
		}
		this.load--;
		emit('deactivate', [load]);
	}
}

class ProcessContext {
	public var ip:IP;
	public var nodeInstance:Component;
	public var port:Dynamic;
	public var result:Dynamic;
	public var scope:String;
	public var activated:Bool;
	public var deactivated:Bool;

	public function new(ip:IP, nodeInstance:Component, port:Dynamic, result:Dynamic) {
		this.ip = ip;
		this.nodeInstance = nodeInstance;
		this.port = port;
		this.result = result;

		this.scope = ip.scope;
		this.activated = false;
		this.deactivated = false;
	}

	public function activate() {
		// Push a new result value if previous has been sent already
		if (result.__resolved || this.nodeInstance.outputQ.indexOf(result) == -1)
			result = {};
		nodeInstance.activate(this);
	}

	public function deactivate() {
		if (!result.__resolved)
			result.__resolved = true;
		nodeInstance.deactivate(this);
	}
}

class ProcessInput {
	public var ports:Dynamic;
	public var context:ProcessContext;
	public var ip:IP;
	public var nodeInstance:Component;
	public var port:BasePort;
	public var result:Dynamic;
	public var scope:String;

	public function new(ports:Dynamic, context:ProcessContext) {
		this.ports = ports;
		this.context = context;

		this.nodeInstance = this.context.nodeInstance;
		this.ip = this.context.ip;
		this.port = this.context.port;
		this.result = this.context.result;
		this.scope = this.context.scope;
	}

	/**
	 * When preconditions are met, set component state to `activated`
	 */
	public function activate() {
		if (context.activated) {
			return;
		}
		if (nodeInstance.isOrdered()) {
			/**
			 * We're handling packets in order. Set the result as non-resolved
			 * so that it can be send when the order comes up
			 */
			result.__resolved = false;
		}
		nodeInstance.activate(context);
		if (port.isAddressable()) {
			trace('${nodeInstance.nodeId} packet on "${port.name}[${ip.index}]" caused activation ${nodeInstance.load}: ${ip.type}');
		} else {
			trace('${nodeInstance.nodeId} packet on "${port.name}" caused activation ${nodeInstance.load}: ${ip.type}');
		}
	}

	/**
	 * Connection listing
	 *
	 * This allows components to check which input ports are attached. This is
	 * useful mainly for addressable ports
	 */
	public function attached(args:Array<Dynamic>) {
		if (args.length == 0) {
			args = ['in'];
		}

		var res = [];
		for (port in args) {
			if (Reflect.field(ports, port) == null) {
				throw 'Node ${nodeInstance.nodeId} has no port "${port}"';
			}
			res.push(Reflect.field(ports, port).listAttached());
		}
		if (args.length == 1) {
			res.pop();
		}

		return res;
	}

	/**
	 * Input preconditions
	 *
	 * When the processing function is called, it can check if input buffers
	 * contain the packets needed for the process to fire.
	 * This precondition handling is done via the `has` and `hasStream` methods.
	 *
	 * Returns true if a port (or ports joined by logical AND) has a new IP
	 * Passing a validation callback as a last argument allows more selective
	 * checking of packets.
	 *
	 * @param args
	 */
	public function has(args:Array<Dynamic>) {
		if (args.length == 0) {
			args = ['in'];
		}
		var validate:Dynamic;

		if (Reflect.isFunction(args[args.length - 1])) {
			validate = args.pop();
		} else {
			validate = function() return true;
		}
		for (port in args) {
			if (Std.is(port, Array)) {
				if (Reflect.field(ports, port[0]) == null) {
					throw 'Node ${nodeInstance.nodeId} has no port "${port[0]}"';
				}
				if (!Reflect.field(ports, port[0]).isAddressable()) {
					throw 'Non-addressable ports, access must be with string ${port[0]}';
				}
				if (!Reflect.field(ports, port[0]).has(scope, port[1], validate)) {
					return false;
				}
				continue;
			}
			if (Reflect.field(ports, port) == null) {
				throw 'Node ${nodeInstance.nodeId} has no port "${port}"';
			}
			if (Reflect.field(ports, port).isAddressable()) {
				throw 'For addressable ports, access must be with array [${port}, idx]';
			}
			if (!Reflect.field(ports, port).has(scope, null, validate)) {
				return false;
			}
		}

		return true;
	}

	public function hasData(args:Array<Dynamic>) {
		if (args.length == 0) {
			args = ['in'];
		}

		args.push(function(ip) {
			return ip.type == 'data';
		});

		return this.has(args);
	}

	public function hasStream(args:Array<Dynamic>) {
		var validateStream:Dynamic;
		if (args.length == 0) {
			args = ['in'];
		}
		if (Reflect.isFunction(args[args.length - 1])) {
			validateStream = args.pop();
		} else {
			validateStream = function(args:Array<Dynamic>) {
				return true;
			};
		}
		for (port in args) {
			var portBrackets = [];
			var dataBrackets = [];
			var hasData = false;
			var validate = function(ip:IP) {
				if (ip.type == 'openBracket') {
					portBrackets.push(ip.data);
					return false;
				}
				if (ip.type == 'data') {
					// Run the stream validation callback
					hasData = validateStream([ip, portBrackets]);
					if (portBrackets.length == 0) {
						// Data IP on its own is a valid stream
						return hasData;
					}
					// Otherwise we need to check for complete stream
					return false;
				}
				if (ip.type == 'closeBracket') {
					portBrackets.pop();
					if (portBrackets.length > 0) {
						return false;
					}
					if (!hasData) {
						return false;
					}
					return true;
				}
			};
			if (!this.has([port, validate])) {
				return false;
			}
		}
		return true;
	}

	/**
	 * Input processing
	 *
	 * Once preconditions have been met, the processing function can read from
	 * the input buffers. Reading packets sets the component as "activated".
	 *
	 * @param args
	 */
	public function get(args:Array<Dynamic>) {
		activate();

		if (args.length == 0) {
			args = ['in'];
		}
		var res = [];
		for (port in args) {
			var portName:Dynamic;
			var idx:Dynamic;
			if (Std.is(port, Array)) {
				portName = port[0];
				idx = port[1];

				if (Reflect.field(ports, portName).isAddressable()) {
					throw 'Non-addressable ports, access must be with string portname';
				}
			} else {
				portname = port;
				if (Reflect.field(ports, portName).isAddressable()) {
					throw 'For addressable ports, access must be with array [portname, idx]';
				}
			}
			if (nodeInstance.isForwardingInport(portname)) {
				var ip = this.__getForForwarding(portname, idx);
				res.push(ip);
				continue;
			}

			ip = Reflect.field(ports, portName).get(scope, idx);
			res.push(ip);

			if (args.length == 1)
				return res[0];
			else
				return res;
		}
	}

	private function __getForForwarding(port:String, idx:Dynamic):IP {
		var prefix = [];
		var dataIp:IP = null;

		// Read IPs until we hit data
		while (true) {
			// Read next packet
			// Read IPs until we hit data
			ip = Reflect.field(ports, port).get(this.scope, idx);
			if (ip == null) {
				// Stop at the end of the buffer
				break;
			}
			if (ip.type == 'data') {
				// Hit the data IP, stop here
				dataIp = ip;
				break;
			}
			// Keep track of bracket closings and openings before
			prefix.push(ip);
		}

		// Forwarding brackets that came before data packet need to manipulate context
		// and be added to result so they can be forwarded correctly to ports that
		// need them

		for (ip in prefix) {
			if (ip.type == 'closeBracket') {
				if (this.result.__bracketClosingBefore == null) {
					// Bracket closings before data should remove bracket context
					this.result.__bracketClosingBefore = [];
				}
				context = this.nodeInstance.getBracketContext('in', port, this.scope, idx).pop();
				context.closeIp = ip;
				this.result.__bracketClosingBefore.push(context);
				continue;
			}
			if (ip.type == 'openBracket') {
				// Bracket openings need to go to bracket context
				this.nodeInstance.getBracketContext('in', port, this.scope, idx).push({
					ip: ip,
					ports: [],
					source: port
				});
				continue;
			}
		}
		if (this.result.__bracketContext == null) {
			// Add current bracket context to the result so that when we send
			// to ports we can also add the surrounding brackets
			this.result.__bracketContext = {};
		}
		Reflect.setField(this.result.__bracketContext, port, this.nodeInstance.getBracketContext('in', port, this.scope, idx).slice(0));
		// Bracket closings that were in buffer after the data packet need to
		// be added to result for done() to read them from
		return dataIp;
	}

	/**
	 * Fetches `data` property of IP object(s) for given port(s)
	 * @param args
	 */
	public function getData(args:Array<Dynamic>) {
		if (args.length == 0) {
			args = ['in'];
		}
		var datas = [];
		for (port in args) {
			var packet = this.get(port);
			if (packet == null) {
				// we add the null packet to the array so when getting
				// multiple ports, if one is null we still return it
				// so the indexes are correct.
				datas.push(packet);
				continue;
			}
			while (packet.type != 'data') {
				packet = this.get(port);
				if (!packet) {
					break;
				}
			}
			datas.push(packet.data);
		}
		if (args.length == 1) {
			return datas.pop();
		}
		return datas;
	}

	public function getStream(args:Array<Dynamic>) {
		if (args.length == 0) {
			args = ['in'];
		}
		var datas = [];
		for (port in args) {
			var portBrackets = [];
			var portPackets = [];
			var hasData = false;
			var ip = this.get(port);
			if (ip == null) {
				datas.push(null);
			}
			while (ip != null) {
				if (ip.type == 'openBracket') {
					if (portBrackets.length == 0) {
						// First openBracket in stream, drop previous
						portPackets = [];
						hasData = false;
					}
					portBrackets.push(ip.data);
					portPackets.push(ip);
				}
				if (ip.type == 'data') {
					portPackets.push(ip);
					hasData = true;
					if (portBrackets.length == 0) {
						// Unbracketed data packet is a valid stream
						break;
					}
				}
				if (ip.type == 'closeBracket') {
					portPackets.push(ip);
					portBrackets.pop();
					if (hasData && portBrackets.length == 0) {
						// Last close bracket finishes stream if there was data inside
						break;
					}
				}
				ip = this.get(port);
			}
			datas.push(portPackets);
		}
		if (args.length == 1) {
			return datas.pop();
		}
		return datas;
	}
}

class ProcessOutput {
	public function new(ports:Dynamic, context:ProcessContext) {}
}
