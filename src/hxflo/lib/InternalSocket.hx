/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 * (c) 2011-2012 Henri Bergius, Nemein
 *
 * HxFlo may be freely distributed under the MIT license
 */

package hxflo.lib;


import EventEmitter;

/**
 * Internal Sockets
 * The default communications mechanism between NoFlo processes is
 * an _internal socket_, which is responsible for accepting information
 * packets sent from processes' outports, and emitting corresponding
 * events so that the packets can be caught to the inport of the
 * connected process.
 */
class InternalSocket extends EventEmitter {
	public var metadata:Dynamic;
	public var brackets:Array<Dynamic> = [];
	public var connected:Bool = false;
	public var dataDelegate:Void->Dynamic;
	public var debug:Bool = false;
	public var emitEvent:String->Array<Dynamic>->EventEmitter;
	public var to:Dynamic;
	public var from:Dynamic;

	public function regularEmitEvent(event:String, data:Array<Dynamic>) {
		return this.emit(event, data);
	}

	public function debugEmitEvent(event:String, data:Array<Dynamic>) {
		try {
			return this.emit(event, data);
		} catch (e:Dynamic) {
			if (this.listeners('error').length == 0) {
				throw e;
			}
			return this.emit('error', [{
				id: this.to.process.id,
				error: e,
				metadata: this.metadata
			}]);
		}
	}

	public function new(?metadata:Dynamic) {
		super();
		this.metadata = metadata != null ? metadata : {};
		this.brackets = [];
		this.connected = false;
		this.dataDelegate = null;
		this.debug = false;
		this.emitEvent = this.regularEmitEvent;
	}

	/**
	 * Socket Connections
	 *
	 * Sockets that are attached to the ports of processes may be
	 * either connected or disconnected. The semantical meaning of
	 * a connection is that the outport is in the process of sending
	 * data. Disconnecting means an end of transmission.
	 *
	 * This can be used for example to signal the beginning and end
	 * of information packets resulting from the reading of a single
	 * file or a database query.
	 */
	public function connect() {
		if (this.connected) {
			return;
		}

		this.connected = true;
		this.emitEvent('connect', []);
	}

	public function disconnect() {
		if (!this.connected) {
			return;
		}

		this.connected = false;
		this.emitEvent('disconnect', []);
	}

	public function isConnected() {
		return this.connected;
	}

	/**
	 * Sending information packets
	 * The _send_ method is used by a processe's outport to
	 * send information packets. The actual packet contents are
	 * not defined by HxFlo, and may be any valid Haxe data
	 * structure
	 *
	 * The packet contents however should be such that may be safely
	 * serialized or deserialized via JSON. This way the HxFlo networks
	 * can be constructed with more flexibility, as file buffers or
	 * message queues can be used as additional packet relay mechanisms.
	 * @param data
	 */
	public function send(data:Dynamic) {
		if (Reflect.isFunction(dataDelegate) && data == null) {
			data = this.dataDelegate();
		}

		this.handleSocketEvent('data', data);
	}

	/**
	 * Sending information packets without open bracket
	 *
	 * As _connect_ event is considered as open bracket, it needs to be followed
	 * by a _disconnect_ event or a closing bracket. In the new simplified
	 * sending semantics single IP objects can be sent without open/close brackets.
	 *
	 * @param ip
	 * @param autoDisconnect = true
	 */
	public function post(ip:IP, autoDisconnect = true) {
		if (Reflect.isFunction(dataDelegate) && ip == null) {
			ip = this.dataDelegate();
		}

		// Send legacy connect/disconnect if needed
		if (!isConnected() && this.brackets.length == 0) {
			connect();
		}
		handleSocketEvent('ip', ip, false);
		if (autoDisconnect && isConnected() && brackets.length == 0) {
			disconnect();
		}
	}

	/**
	 * Information Packet grouping
	 *
	 * Processes sending data to sockets may also group the packets
	 * when necessary. This allows transmitting tree structures as
	 * a stream of packets.
	 *
	 * For example, an object could be split into multiple packets
	 * where each property is identified by a separate grouping:
	 *
	 * ```
	 *  // Group by object ID
	 *  outPorts.out.beginGroup(object.get('id'));
	 *
	 *  for (key in object.keys()) {
	 *      outPorts.out.beginGroup(property);
	 *      outPorts.out.send(value);
	 *      outPorts.out.endGroup();
	 *  }
	 *  outPorts.out.endGroup()
	 * ```
	 *
	 * This would cause a tree structure to be sent to the receiving
	 * process as a stream of packets. So, an article object may be
	 * as packets like:
	 *
	 * `/<article id>/title/Lorem ipsum`
     * 
	 * `/<article id>/author/Henri Bergius`
	 *
	 * Components are free to ignore groupings, but are recommended
	 * to pass received groupings onward if the data structures remain
	 * intact through the component's processing.
	 *
	 * @param group
	 */
	public function beginGroup(group:Dynamic) {
		handleSocketEvent('begingroup', group);
	}

	public function endGroup() {
		handleSocketEvent('endgroup');
	}

	/**
	 * Socket data delegation
	 *
	 * Sockets have the option to receive data from a delegate function
	 * should the `send` method receive undefined for `data`.  This
	 * helps in the case of defaulting values.
	 * @param delegate
	 */
	public function setDataDelegate(delegate:Void->Dynamic) {
		if (delegate == null) {
			throw 'A data delegate must be a function.';
		}

		this.dataDelegate = delegate;
	}

	/**
	 * Socket debug mode
	 *
	 * Sockets can catch exceptions happening in processes when data is
	 * sent to them. These errors can then be reported to the network for
	 * notification to the developer.
	 * @param active
	 */
	public function setDebug(active:Bool) {
		debug = active;
		emitEvent = debug ? debugEmitEvent : regularEmitEvent;
	}

	public function getId():String {
		var fromStr = function(from:Dynamic):String {
			return '${from.process.id}() ${from.port.toUpperCase()}';
		}

		var toStr = function(to:Dynamic):String {
			return '${to.port.toUpperCase()} ${to.process.id}()';
		}

		if (!(from != null || to != null)) {
			return 'UNDEFINED';
		} else if (from != null && to == null) {
			return '${fromStr(from)} -> ANON';
		} else if (from == null) {
			return '${fromStr(from)} -> ${toStr(to)}';
		}

		return '';
	}

	public function legacyToIp(event:String, payload:Dynamic):IP {
		// No need to wrap modern IP Objects
		if (IP.isIP(payload)) {
			return payload;
		}

		// Wrap legacy events into appropriate IP objects
		return switch (event) {
			case 'begingroup': new IP('openBracket', payload);
			case 'endgroup': new IP('closeBracket');
			case 'data': new IP('data', payload);
			case _: null;
		}
	}

    public function ipToLegacy(ip:IP):{event:String, payload:Dynamic} {
        return switch ip.type {
            case 'openBracket': {
                {
                    event: 'begingroup',
                    payload: ip.data
                }
            }
            case 'data': {
                {
                    event: 'data',
                    payload: ip.data
                }
            }
            case 'closeBracket': {
                {
                    event: 'endgroup',
                    payload: ip.data
                }
            }
            case _: {
               null
            }
        }
    }

    public function handleSocketEvent(event:String, ?payload:Dynamic, autoConnect:Bool = true){
        var isIP:Bool = event == 'ip' && IP.isIP(payload);
        var ip = isIP ? payload : legacyToIp(event, payload);

        if(!ip){
            return;
        }

        if(event == 'begingroup'){
            brackets.push(payload);
        }
        if(isIP && ip.type == 'openBracket'){
            brackets.push(ip.data);
        }

        if(event == 'endGroup'){
            // Prevent closing already closed groups
            if(brackets.length == 0){
                return;
            }
            // Add group name to bracket
            ip.data = brackets.pop();
            payload = ip.data;
        }

        if(isIP && payload.type == 'closeBracket'){
            // Prevent closing already closed brackets
            if (brackets.length == 0) {
                return;
            }
            brackets.pop();
        }

        // Emit the IP Object
        emitEvent('ip', [ip]);

        // Emit the legacy event
        if(ip == null && ip.type == null){
            return;
        }

        if (isIP){
            var legacy = ipToLegacy(ip);
            event = legacy.event;
            payload = legacy.payload;
        }

        this.connected =  event == 'connect' ? true : this.connected;
        this.connected = event == 'disconnect' ? false : this.connected;

    }

	public static function createSocket(?metadata:Dynamic):InternalSocket {
		return new InternalSocket(metadata);
	}
}
