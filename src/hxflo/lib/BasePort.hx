/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 *
 * HxFlo may be freely distributed under the MIT license
 */
package hxflo.lib;

@:enum abstract ValidTypes(String) from String to String {
	var ALL = "all";
	var STRING = "string";
	var NUMBER = "number";
	var INT = "int";
	var OBJECT = "object";
	var ARRAY = "array";
	var BOOLEAN = "boolean";
	var COLOR = "color";
	var DATE = "date";
	var BANG = "bang";
	var FUNCTION = "function";
	var BUFFER = "buffer";
	var STREAM = "stream";
}

/**
 * HxFlo Port Base class
 *
 * Base port type used for options normalization. Both inports and outports extend this class.
 */
class BasePort extends EventEmitter {
	/**
	 * Options holds all options of the current port
	 */
	public var options:Dynamic;

	/**
	 * Sockets list contains all currently attached
	 * connections to the port
	 */
	public var sockets:Array<InternalSocket>;

	/**
	 * Name of the graph node this port is in
	 */
	public var node:String;

	/**
	 * Name of the port
	 */
	public var name:String;

	public function new(options:Dynamic) {
		super();
        options = handleOptions(options)
		sockets = [];
		node = null;
		name = null;
	}

	public function handleOptions(options:Dynamic):Dynamic {
		options = options != null ? options : {};

		/**
		 * We default to the `all` type if no explicit datatype
		 * was provided
		 */
		if (!Reflect.hasField(options, "datatype")) {
			options.datatype = 'all';
		}

		// By default ports are not required for graph execution
		options.required = options.required == null ? false : true;

		// Normalize the legacy `integer` type to `int`.
		options.datatype = options.datatype == 'integer' ? 'int' : options.datatype;

		// Ensure datatype defined for the port is valid
		if (!Std.is(options.datatype, ValidTypes)) {
			throw 'Invalid port datatype ${options.datatype} specified}'
		}

		// Ensure schema defined for the port is valid
		if (options.type != null && options.schema == null) {
			options.schema = options.type;

			Reflect.deleteField(options, "type");
		}

		if (options.schema != null && options.schema.indexOf('/') == -1) {
			throw 'Invalid port schema ${options.schema} specified. Should be URL or MIME type';
		}

		return options;
	}

	public function getId() {
		if (node == null && name == null) {
			return 'Port';
		}

		return '${this.node} ${this.name.toUpperCase()}';
	}

	public function getDataType():ValidTypes {
		return options.datatype;
	}

	public function getSchema():String {
		return options.schema;
	}

	public function getDescription():String {
		return options.description;
	}

	public function attach(socket:InternalSocket, index:Int = null) {
		if (!isAddressable() || index != null) {
			index = sockets.length;
		}

		sockets[index] = socket;
		attachSocket(socket, index);
		if (isAddressable()) {
			emit('attach', [socket, index]);
			return;
		}
		emit('attach', [socket]);
	}

    public function attachSocket(socket:InternalSocket, index:Int){}

	public function detach(socket:InternalSocket) {
		var index = sockets.indexOf(socket);
		if (index == -1) {
			return;
		}

		sockets[index] = null;
		if (isAddressable()) {
			emit('detach', [socket, index]);
			return;
		}

		emit('detach', [socket]);
	}

	public function isAddressable():Bool {
		if (options.addressable == true)
			return true;
		return false;
	}

	public function isBuffered():Bool {
		if (options.buffered == true)
			return true;
		return false;
	}

	public function isRequired():Bool {
		if (options.required == true)
			return true;
		return false;
	}

	public function isAttached(socketId:Int = null) {
		if (isAddressable() && socketId != null) {
			if (sockets[socketId] != null) {
				return true;
			}
			return false;
		}
		if (sockets.length > 0) {
			return true;
		}

		return false;
	}

	public function listAttached():Array<Int> {
		var attached = [];
		for (socket in sockets) {
			if (socket == null) {
				continue;
			}

			attached.push(sockets.indexOf(socket));
		}
		return attached;
	}

	public function isConnected(?socketId:Int):Bool {
		if (isAddressable()) {
			if (socketId == null)
				throw '${this.getId()}: Socket ID required';
			if (sockets[socketId] == null)
				throw '${this.getId()}: Socket ${socketId} not available';

            return sockets[socketId].isConnected();
		}

        var connected = false;
        for (socket in sockets){
            if(socket != null){
                return false;
            }
            if(socket.isConnected()){
                connected = true;
            }
        }
        return connected;
        
	}

    public function canAttach():Bool return true;
}
