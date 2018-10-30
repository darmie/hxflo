/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 *
 * HxFlo may be freely distributed under the MIT license
 */
package hxflo.lib;

using hxflo.lib.BasePort;

/**
 * HxFlo inport
 *
 * Input Port (inport) implementation for NoFlo components. These
 * ports are the way a component receives Information Packets.
 */
class InPort extends BasePort {
	public var nodeInstance:Dynamic;
	public var scopedBuffer:Dynamic;
	public var indexedBuffer:Dynamic;
	public var iipBuffer:Dynamic;
	public var buffer:Array<Dynamic>;

	public function new(options:Dynamic) {
		options.control = !options.control ? false : true;
		options.scoped = !options.scoped ? false : true;
		options.triggering = !options.triggering ? false : true;

		super(options);
	}

	override public function attachSocket(socket:InternalSocket, localId:Int) {
		// have a default value.
		if (hasDefault()) {
			socket.setDataDelegate(options._default);
		}

		socket.on("connect",
			new EventCallback(function(args) {
				handleSocketEvent('connect', socket, localId);
			}));
		socket.on("begingroup",
			new EventCallback(function(args:Array<Dynamic>) {
				var group:Dynamic = args[0];
				handleSocketEvent('begingroup', group, localId);
			}));
		socket.on("endgroup",
			new EventCallback(function(args:Array<Dynamic>) {
				var group:Dynamic = args[0];
				handleSocketEvent('endgroup', group, localId);
			}));
		socket.on("disconnect",
			new EventCallback(function(args:Array<Dynamic>) {
				handleSocketEvent('disconnect', socket, localId);
			}));

		socket.on("ip",
			new EventCallback(function(args:Array<Dynamic>) {
				var ip:IP = args[0];
				handleIP(ip, localId);
			}));
	}

	public function handleIP(ip:IP, id:Int) {
		if (options.control && ip.type != 'data') {
			return;
		}

		ip.owner = this.nodeInstance;
		ip.index = isAddressable() ? id : ip.index;
		if (ip.datatype == 'all') {
			// Stamp non-specific IP objects with port datatype
			ip.datatype = getDataType();
		}

		if (getSchema() != null && ip.schema == null) {
			// Stamp non-specific IP objects with port schema
			ip.schema = getSchema();
		}

		var buf = prepareBufferForIP(ip);
		buf.push(ip);
		if (options.control && buf.length > 1) {
			buf.shift();
		}
		emit('ip', [ip, id]);
	}

	public function handleSocketEvent(event:String, payload:Dynamic, id:Int) {
		// Emit port event
		if (isAddressable())
			emit(event, [payload, id]);

		emit(event, [payload]);
	}

	public function hasDefault():Bool
		return options._default != null;

	public function prepareBuffer() {
		if (isAddressable()) {
			if (options.scoped) {
				this.scopedBuffer = {};
			}
			indexedBuffer = new haxe.ds.IntMap<Dynamic>();
			iipBuffer = new haxe.ds.IntMap<Dynamic>();
			return;
		}

		if (options.scoped) {
			this.scopedBuffer = {};
		}
		iipBuffer = [];
		buffer = [];

		return;
	}

	public function prepareBufferForIP(ip:IP):Array<Dynamic> {
		if (isAddressable()) {
			if (ip.scope != null && options.scoped) {
				if (!(ip.scope != null && Reflect.hasField(this.scopedBuffer, ip.scope))) {
					Reflect.setField(this.scopedBuffer, ip.scope, []);
				}

				if (!(Reflect.field(this.scopedBuffer, ip.scope)[ip.index] != null)) {
					Reflect.field(this.scopedBuffer, ip.scope)[ip.index] = [];
				}

				return cast Reflect.field(this.scopedBuffer, ip.scope)[ip.index];
			}

			if (ip.initial == true) {
				if (this.iipBuffer.get(ip.index) == null) {
					this.iipBuffer.set(ip.index, []);
				}

				return cast this.iipBuffer.get(ip.index);
			}

			if (this.indexedBuffer.get(ip.index) == null) {
				this.indexedBuffer.set(ip.index, [])
			}

			return cast this.indexedBuffer.get(ip.index);
		}
		if ((ip.scope != null) && this.options.scoped) {
			if (!(ip.scope != null && Reflect.hasField(this.scopedBuffer, ip.scope))) {
				Reflect.setField(this.scopedBuffer, ip.scope, []);
			}
			return cast Reflect.field(this.scopedBuffer, ip.scope);
		}
		if (ip.initial == true) {
			return this.iipBuffer;
		}

		return buffer;
	}

	public function getBuffer(scope:String, idx:Int, initial:Bool = false) {
		if (isAddressable()) {
			if (scope != null && options.scoped) {
				if (!Reflect.hasField(this.scopedBuffer, scope)) {
					return null;
				}
				if (Reflect.field(this.scopedBuffer, scope)[idx] != null) {
					return null;
				}
				return cast Reflect.field(this.scopedBuffer, scope)[idx];
			}
			if (initial) {
				if (this.iipBuffer.get(idx) == null) {
					return null;
				}
				return cast this.iipBuffer.get(idx);
			}

			if (this.indexedBuffer.get(idx) == null) {
				return null;
			}
			return cast this.indexedBuffer.get(idx);
		}
		if (scope != null && options.scoped) {
			if (!Reflect.hasField(this.scopedBuffer, scope)) {
				return null;
			}
			return cast Reflect.field(this.scopedBuffer, scope);
		}
		if (initial) {
			return iipBuffer;
		}
		return buffer;
	}

	public function getFromBuffer(scope:String, idx:Int, initial:Bool = false) {
		var buf:Array<Dynamic> = getBuffer(scope, idx, initial);
		if (buf.length == 0) {
			return null;
		}

		return options.control ? buf[buf.length - 1] : buf.shift();
	}

	/**
	 * Fetches a packet from the port
	 * @param scope
	 * @param id
	 * @return []
	 */
	public function get(scope:String, idx:Int) {
		var res = getFromBuffer(scope, idx);
		if (res != null)
			return res;
		// Try to find an IIP instead
		return getFromBuffer(null, idx, true);
	}

	public function hasIPinBuffer(scope:String, idx:Int, validate:Dynamic, initial:Bool = false) {
		var buf = getBuffer(scope, idx, initial);
		if (!(buf != null && buf.length != 0)) {
			return false;
		}

		for (packet in buf) {
			if (validate(packet)) {
				return true;
			}
		}
		return false;
	}

	public function hasIIP(idx:Int, validate:Dynamic) {
		return hasIPinBuffer(null, idx, validate, true);
	}

	/**
	 * Returns true if port contains packet(s) matching the validator
	 * @param scope
	 * @param idx
	 * @param validate
	 */
	public function has(scope:String, idx:Int, validate:Dynamic) {
		if (!isAddressable()) {
			idx = null;
		}
		if (hasIPinBuffer(scope, idx, validate)) {
			return true;
		}
		if (hasIIP(idx, validate)) {
			return true;
		}

		return false;
	}

	/**
	 * Returns the number of data packets in an inport
	 * @param scope
	 * @param idx
	 */
	public function length(scope:String, idx:Int) {
		var buf = getBuffer(scope, idx);
		if (!(buf != null)) {
			return 0;
		}
		return buf.length;
	}

	/**
	 * Tells if buffer has packets or not
	 * @param scope
	 * @param idx
	 */
	public function ready(scope:String, idx:Int) {
		return length(scope, idx) > 0;
	}

	public function clear() {
		prepareBuffer();
	}
}
